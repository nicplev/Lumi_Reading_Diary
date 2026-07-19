import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import '../models/remote_message.dart';

enum RemoteMessageConfigState {
  checking,
  available,

  /// No cached policy exists and the endpoint could not be reached.
  ///
  /// This is deliberately distinct from [unavailable]: the app may continue
  /// while the controller retries because no invalid policy was received.
  temporarilyUnavailable,

  /// Local storage failed or the endpoint returned an invalid response.
  unavailable,
}

/// Polls the Cloudflare status worker for an out-of-band message that the
/// app can render even when Firebase is down.
///
/// The endpoint MUST NOT depend on Firebase — that's the whole point. The
/// controller polls every [pollInterval] when foregrounded, caches the
/// last successful response in a Hive box, and falls back to the cached
/// value on fetch failure. An empty payload (`id == null`) hides the
/// banner but does NOT clear the cache.
class RemoteMessageController with WidgetsBindingObserver {
  RemoteMessageController._({
    required Uri endpoint,
    http.Client? httpClient,
    Duration pollInterval = const Duration(seconds: 60),
    Duration requestTimeout = const Duration(seconds: 5),
    List<Duration> recoveryDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 30),
      Duration(seconds: 60),
    ],
    String cacheBoxName = 'remote_message',
    String dismissalsBoxName = 'dismissed_messages',
  })  : _endpoint = endpoint,
        _http = httpClient ?? http.Client(),
        _pollInterval = pollInterval,
        _requestTimeout = requestTimeout,
        _recoveryDelays = recoveryDelays,
        _cacheBoxName = cacheBoxName,
        _dismissalsBoxName = dismissalsBoxName;

  static RemoteMessageController? _instance;

  /// Initialize the singleton with the production Worker endpoint.
  /// Safe to call multiple times — subsequent calls are no-ops.
  static RemoteMessageController ensureInstance(Uri endpoint) {
    return _instance ??= RemoteMessageController._(endpoint: endpoint);
  }

  static RemoteMessageController get instance {
    final i = _instance;
    if (i == null) {
      throw StateError(
        'RemoteMessageController.ensureInstance(endpoint) must be called '
        'before .instance is read.',
      );
    }
    return i;
  }

  @visibleForTesting
  factory RemoteMessageController.forTest({
    required Uri endpoint,
    http.Client? httpClient,
    Duration pollInterval = const Duration(milliseconds: 200),
    Duration requestTimeout = const Duration(seconds: 1),
    List<Duration> recoveryDelays = const [Duration(milliseconds: 20)],
    String cacheBoxName = 'remote_message_test',
    String dismissalsBoxName = 'dismissed_messages_test',
  }) {
    return RemoteMessageController._(
      endpoint: endpoint,
      httpClient: httpClient,
      pollInterval: pollInterval,
      requestTimeout: requestTimeout,
      recoveryDelays: recoveryDelays,
      cacheBoxName: cacheBoxName,
      dismissalsBoxName: dismissalsBoxName,
    );
  }

  final Uri _endpoint;
  final http.Client _http;
  final Duration _pollInterval;
  final Duration _requestTimeout;
  final List<Duration> _recoveryDelays;
  final String _cacheBoxName;
  final String _dismissalsBoxName;

  late Box<Map> _cacheBox;
  late Box<bool> _dismissalsBox;

  final StreamController<RemoteMessage?> _output =
      StreamController<RemoteMessage?>.broadcast();
  Stream<RemoteMessage?> get stream => _output.stream;

  final StreamController<RemoteMessageConfigState> _configStateOutput =
      StreamController<RemoteMessageConfigState>.broadcast();
  Stream<RemoteMessageConfigState> get configStateStream =>
      _configStateOutput.stream;

  Timer? _pollTimer;
  Timer? _recoveryTimer;
  int _recoveryAttempt = 0;
  Future<RemoteMessage?>? _refreshInFlight;
  bool _foregrounded = true;
  bool _initialized = false;
  RemoteMessage? _current;
  RemoteMessage? get current => _current;
  RemoteMessageConfigState _configState = RemoteMessageConfigState.checking;
  RemoteMessageConfigState get configState => _configState;

  void _setConfigState(RemoteMessageConfigState value) {
    if (_configState == value) return;
    _configState = value;
    if (!_configStateOutput.isClosed) _configStateOutput.add(value);
  }

  void _markAvailable() {
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _recoveryAttempt = 0;
    _setConfigState(RemoteMessageConfigState.available);
  }

  void _markTransientlyUnavailable() {
    if (_current != null) {
      _markAvailable();
      return;
    }
    _setConfigState(RemoteMessageConfigState.temporarilyUnavailable);
    _scheduleRecoveryRetry();
  }

  void _markInvalidConfiguration() {
    if (_current != null) {
      _markAvailable();
      return;
    }
    _setConfigState(RemoteMessageConfigState.unavailable);
  }

  void _scheduleRecoveryRetry() {
    if (_recoveryTimer != null || _recoveryDelays.isEmpty) return;
    final index = _recoveryAttempt.clamp(0, _recoveryDelays.length - 1);
    final delay = _recoveryDelays[index];
    _recoveryAttempt++;
    _recoveryTimer = Timer(delay, () {
      _recoveryTimer = null;
      if (_foregrounded) unawaited(refresh());
    });
  }

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      _cacheBox = await Hive.openBox<Map>(_cacheBoxName);
      _dismissalsBox = await Hive.openBox<bool>(_dismissalsBoxName);
    } catch (_) {
      _setConfigState(RemoteMessageConfigState.unavailable);
      rethrow;
    }
    _initialized = true;

    // Emit any cached message immediately so we don't show a stale
    // "everything is fine" UI for the first ~60s after launch when there
    // was an active outage at last close.
    final cached = _cacheBox.get('current');
    if (cached != null) {
      try {
        _current = RemoteMessage.fromCache(Map<String, dynamic>.from(cached));
        _markAvailable();
        _output.add(_current);
      } catch (e) {
        debugPrint('RemoteMessageController: cache decode failed: $e');
      }
    }

    WidgetsBinding.instance.addObserver(this);
    _startPolling();
    // With no cache, wait for one bounded request so release startup can make
    // an explicit allow/update/support decision. With a cache, render at once
    // and refresh opportunistically in the background.
    if (_current == null) {
      await refresh();
    } else {
      unawaited(refresh());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foregroundNow = state == AppLifecycleState.resumed;
    if (foregroundNow == _foregrounded) return;
    _foregrounded = foregroundNow;
    if (foregroundNow) {
      _startPolling();
      unawaited(refresh());
    } else {
      _pollTimer?.cancel();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (!_foregrounded) return;
      unawaited(refresh());
    });
  }

  /// Fetches once. Failures silently fall back to the cached message.
  ///
  /// With no cache, transport failures are recoverable and retry on a short
  /// backoff. Invalid responses remain a hard configuration failure so a bad
  /// policy cannot silently disable the release gate.
  Future<RemoteMessage?> refresh() async {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;
    final operation = _performRefresh();
    _refreshInFlight = operation;
    try {
      return await operation;
    } finally {
      if (identical(_refreshInFlight, operation)) _refreshInFlight = null;
    }
  }

  Future<RemoteMessage?> _performRefresh() async {
    if (_current == null &&
        _configState != RemoteMessageConfigState.temporarilyUnavailable) {
      _setConfigState(RemoteMessageConfigState.checking);
    }
    try {
      final resp = await _http.get(_endpoint).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        if (resp.statusCode == 408 ||
            resp.statusCode == 429 ||
            resp.statusCode >= 500) {
          _markTransientlyUnavailable();
        } else {
          _markInvalidConfiguration();
        }
        return _current;
      }
      Object? json;
      try {
        json = jsonDecode(resp.body);
      } catch (e) {
        debugPrint('RemoteMessageController: invalid JSON response: $e');
        _markInvalidConfiguration();
        return _current;
      }
      if (json is! Map<String, dynamic>) {
        _markInvalidConfiguration();
        return _current;
      }
      RemoteMessage fresh;
      try {
        fresh = RemoteMessage.fromJson(json, fetchedAt: DateTime.now());
      } catch (e) {
        debugPrint('RemoteMessageController: invalid policy response: $e');
        _markInvalidConfiguration();
        return _current;
      }
      // Persist before emitting so a crash mid-emit doesn't lose state.
      await _cacheBox.put('current', fresh.toJson());
      if (_current == null ||
          _current!.dismissalKey != fresh.dismissalKey ||
          _current!.message != fresh.message) {
        _current = fresh;
        if (!_output.isClosed) _output.add(fresh);
      } else {
        _current = fresh;
      }
      _markAvailable();
      return fresh;
    } on TimeoutException catch (e) {
      debugPrint('RemoteMessageController: refresh failed: $e');
      _markTransientlyUnavailable();
      return _current;
    } on http.ClientException catch (e) {
      debugPrint('RemoteMessageController: refresh failed: $e');
      _markTransientlyUnavailable();
      return _current;
    } catch (e) {
      debugPrint('RemoteMessageController: policy processing failed: $e');
      _markInvalidConfiguration();
      return _current;
    }
  }

  /// User-initiated recovery from the support screen. This also retries Hive
  /// initialization if bootstrap could not open the local policy cache.
  Future<RemoteMessage?> retry() async {
    if (!_initialized) {
      await initialize();
      return _current;
    }
    return refresh();
  }

  bool isDismissed(RemoteMessage message) {
    return _dismissalsBox.get(message.dismissalKey) == true;
  }

  Future<void> dismiss(RemoteMessage message) async {
    await _dismissalsBox.put(message.dismissalKey, true);
    if (!_output.isClosed) _output.add(_current);
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _recoveryTimer?.cancel();
    _http.close();
    await _output.close();
    await _configStateOutput.close();
  }
}
