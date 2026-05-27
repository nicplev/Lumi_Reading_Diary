import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import '../models/remote_message.dart';

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
    String cacheBoxName = 'remote_message',
    String dismissalsBoxName = 'dismissed_messages',
  })  : _endpoint = endpoint,
        _http = httpClient ?? http.Client(),
        _pollInterval = pollInterval,
        _requestTimeout = requestTimeout,
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
    String cacheBoxName = 'remote_message_test',
    String dismissalsBoxName = 'dismissed_messages_test',
  }) {
    return RemoteMessageController._(
      endpoint: endpoint,
      httpClient: httpClient,
      pollInterval: pollInterval,
      requestTimeout: requestTimeout,
      cacheBoxName: cacheBoxName,
      dismissalsBoxName: dismissalsBoxName,
    );
  }

  final Uri _endpoint;
  final http.Client _http;
  final Duration _pollInterval;
  final Duration _requestTimeout;
  final String _cacheBoxName;
  final String _dismissalsBoxName;

  late Box<Map> _cacheBox;
  late Box<bool> _dismissalsBox;

  final StreamController<RemoteMessage?> _output =
      StreamController<RemoteMessage?>.broadcast();
  Stream<RemoteMessage?> get stream => _output.stream;

  Timer? _pollTimer;
  bool _foregrounded = true;
  bool _initialized = false;
  RemoteMessage? _current;
  RemoteMessage? get current => _current;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _cacheBox = await Hive.openBox<Map>(_cacheBoxName);
    _dismissalsBox = await Hive.openBox<bool>(_dismissalsBoxName);

    // Emit any cached message immediately so we don't show a stale
    // "everything is fine" UI for the first ~60s after launch when there
    // was an active outage at last close.
    final cached = _cacheBox.get('current');
    if (cached != null) {
      try {
        _current =
            RemoteMessage.fromCache(Map<String, dynamic>.from(cached));
        _output.add(_current);
      } catch (e) {
        debugPrint('RemoteMessageController: cache decode failed: $e');
      }
    }

    WidgetsBinding.instance.addObserver(this);
    _startPolling();
    unawaited(refresh());
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
  Future<RemoteMessage?> refresh() async {
    try {
      final resp = await _http.get(_endpoint).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return _current;
      }
      final json = jsonDecode(resp.body);
      if (json is! Map<String, dynamic>) return _current;
      final fresh =
          RemoteMessage.fromJson(json, fetchedAt: DateTime.now());
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
      return fresh;
    } catch (e) {
      debugPrint('RemoteMessageController: refresh failed: $e');
      return _current;
    }
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
    _http.close();
    await _output.close();
  }
}
