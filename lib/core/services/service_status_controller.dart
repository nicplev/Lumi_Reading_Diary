import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../models/service_status.dart';

/// Layered probe + state machine for [ServiceStatus].
///
/// Owns connectivity_plus, the periodic probe timer, and the broadcast
/// stream that the Riverpod `serviceStatusProvider` exposes to the UI.
///
/// The probe runs in three layers:
///  - L1 device connectivity (from connectivity_plus)
///  - L2 public-internet HEAD (Cloudflare trace, no Firebase dependency)
///  - L3 Firestore `_meta/healthcheck` read with `Source.server`
///
/// L1/L2/L3 are independent so we can tell the user *what* is broken, not
/// just "something is offline."
///
/// Singleton because the only safe way to bound the probe rate is for every
/// caller to share the same scheduler; multiple controllers would multiply
/// Firestore reads with no benefit.
class ServiceStatusController with WidgetsBindingObserver {
  ServiceStatusController._({
    Connectivity? connectivity,
    FirebaseFirestore? firestore,
    http.Client? httpClient,
    // 600s: the steady-state heartbeat is deliberately slow — every tick is
    // a billed server-source Firestore read PER FOREGROUND USER (the old 30s
    // cadence cost ~120 reads/hr/user across the fleet). Fast detection
    // comes from the event-driven probes instead: connectivity changes, app
    // resume, user taps, and OfflineService's enqueue/drain-failure hooks
    // all forceProbe() immediately, so the timer only catches outages no
    // event surfaces. The offline queue makes a stale status safe: writes
    // gated by a stale-healthy status still fail into the queue, and a
    // stale-degraded status just queues writes that drain minutes later.
    Duration periodicInterval = const Duration(seconds: 600),
    Duration debounce = const Duration(milliseconds: 500),
    Duration minProbeInterval = const Duration(seconds: 5),
    Duration probeTimeout = const Duration(seconds: 3),
    Duration coldStartProbeTimeout = const Duration(seconds: 10),
    Duration coldStartRetryDelay = const Duration(seconds: 5),
    Duration degradedThreshold = const Duration(milliseconds: 1500),
    String internetProbeUrl = 'https://1.1.1.1/cdn-cgi/trace',
    String firebaseHealthcheckPath = '_meta/healthcheck',
  })  : _connectivity = connectivity ?? Connectivity(),
        _firestoreOverride = firestore,
        _http = httpClient ?? http.Client(),
        _periodicInterval = periodicInterval,
        _debounce = debounce,
        _minProbeInterval = minProbeInterval,
        _probeTimeout = probeTimeout,
        _coldStartProbeTimeout = coldStartProbeTimeout,
        _coldStartRetryDelay = coldStartRetryDelay,
        _degradedThreshold = degradedThreshold,
        _internetProbeUrl = Uri.parse(internetProbeUrl),
        _firebaseHealthcheckPath = firebaseHealthcheckPath;

  static ServiceStatusController? _instance;
  static ServiceStatusController get instance =>
      _instance ??= ServiceStatusController._();

  /// Test-only constructor. Lets specs inject fakes for every dependency
  /// without going through the real singleton.
  @visibleForTesting
  factory ServiceStatusController.forTest({
    Connectivity? connectivity,
    FirebaseFirestore? firestore,
    http.Client? httpClient,
    Duration periodicInterval = const Duration(seconds: 30),
    Duration debounce = const Duration(milliseconds: 50),
    Duration minProbeInterval = const Duration(milliseconds: 100),
    Duration probeTimeout = const Duration(seconds: 1),
    Duration degradedThreshold = const Duration(milliseconds: 500),
  }) {
    return ServiceStatusController._(
      connectivity: connectivity,
      firestore: firestore,
      httpClient: httpClient,
      periodicInterval: periodicInterval,
      debounce: debounce,
      minProbeInterval: minProbeInterval,
      probeTimeout: probeTimeout,
      degradedThreshold: degradedThreshold,
    );
  }

  final Connectivity _connectivity;
  final FirebaseFirestore? _firestoreOverride;
  final http.Client _http;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  final Duration _periodicInterval;
  final Duration _debounce;
  final Duration _minProbeInterval;
  final Duration _probeTimeout;
  final Duration _coldStartProbeTimeout;
  final Duration _coldStartRetryDelay;
  final Duration _degradedThreshold;
  final Uri _internetProbeUrl;
  final String _firebaseHealthcheckPath;

  final StreamController<ServiceStatusSnapshot> _output =
      StreamController<ServiceStatusSnapshot>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _periodicTimer;
  Timer? _debounceTimer;
  Future<ServiceStatusSnapshot>? _inFlight;
  DateTime? _lastProbeAt;

  /// Tracks the last connectivity result we observed so probes can reason
  /// about L1 without re-querying.
  List<ConnectivityResult> _lastConnectivity = const [];

  /// Flap-suppression: how many consecutive non-healthy probes we've seen
  /// since the last healthy snapshot. We only emit the transition after
  /// two confirming probes so a single flaky read doesn't flash a banner.
  int _consecutiveUnhealthyProbes = 0;

  /// True until the first probe that returns a verdict (healthy or
  /// otherwise) completes. Used to (a) widen the L3 timeout so a warming
  /// Firestore SDK doesn't get falsely flagged, and (b) schedule a fast
  /// re-probe after a suppressed unknown→unhealthy emission so we confirm
  /// or clear the verdict within seconds rather than waiting 600s for the
  /// next periodic tick.
  bool _coldStart = true;
  Timer? _coldStartRetryTimer;

  ServiceStatusSnapshot _current = ServiceStatusSnapshot.unknown();
  ServiceStatusSnapshot get current => _current;

  /// Test-only: force the current snapshot so specs can exercise the online /
  /// offline write branches deterministically without a live connectivity probe.
  @visibleForTesting
  void debugSetCurrent(ServiceStatusSnapshot snapshot) => _current = snapshot;

  bool _initialized = false;
  bool _foregrounded = true;

  Stream<ServiceStatusSnapshot> get stream => _output.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    WidgetsBinding.instance.addObserver(this);

    _connectivitySub =
        _connectivity.onConnectivityChanged.listen(_handleConnectivity);

    try {
      _lastConnectivity = await _connectivity.checkConnectivity();
    } catch (e) {
      debugPrint('ServiceStatusController: initial connectivity check: $e');
      _lastConnectivity = const [ConnectivityResult.none];
    }

    _startPeriodicTimer();
    // Kick off the first probe so `current` resolves out of `unknown`
    // within ~a second of app start. Fire-and-forget on purpose.
    unawaited(_runProbe());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foregroundNow = state == AppLifecycleState.resumed;
    if (foregroundNow == _foregrounded) return;
    _foregrounded = foregroundNow;
    if (foregroundNow) {
      _startPeriodicTimer();
      unawaited(_runProbe());
    } else {
      _periodicTimer?.cancel();
      _debounceTimer?.cancel();
      _coldStartRetryTimer?.cancel();
    }
  }

  void _handleConnectivity(List<ConnectivityResult> results) {
    _lastConnectivity = results;
    if (results.contains(ConnectivityResult.none) && results.length == 1) {
      // Immediate, debounce-free transition into offline so the UI flips
      // the moment the user toggles airplane mode.
      _consecutiveUnhealthyProbes = 0;
      _emit(_buildSnapshot(
        status: ServiceStatus.offline,
        deviceConnected: false,
        internetReachable: false,
        firebaseReachable: false,
      ));
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () => unawaited(_runProbe()));
  }

  void _startPeriodicTimer() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(_periodicInterval, (_) {
      if (!_foregrounded) return;
      unawaited(_runProbe());
    });
  }

  /// Public hook for the "Try syncing now" button. Coalesces with any
  /// in-flight probe so users tapping repeatedly don't multiply load.
  Future<ServiceStatusSnapshot> forceProbe() => _runProbe(forced: true);

  Future<ServiceStatusSnapshot> _runProbe({bool forced = false}) {
    final existing = _inFlight;
    if (existing != null) return existing;

    if (!forced && _lastProbeAt != null) {
      final since = DateTime.now().difference(_lastProbeAt!);
      if (since < _minProbeInterval) {
        return Future.value(_current);
      }
    }

    final future = _probe(forced: forced);
    _inFlight = future;
    return future.whenComplete(() {
      _inFlight = null;
      _lastProbeAt = DateTime.now();
      _coldStart = false;
    });
  }

  void _scheduleColdStartRetry() {
    if (_coldStartRetryTimer?.isActive ?? false) return;
    _coldStartRetryTimer = Timer(_coldStartRetryDelay, () {
      if (!_foregrounded) return;
      unawaited(_runProbe(forced: true));
    });
  }

  Future<ServiceStatusSnapshot> _probe({bool forced = false}) async {
    // Re-check connectivity at probe time. The cached `_lastConnectivity`
    // can lag reality at cold start on iOS — `checkConnectivity()` in
    // `initialize()` sometimes returns `[none]` before the wifi state has
    // propagated, and the `onConnectivityChanged` listener doesn't always
    // re-fire once the OS catches up. Treat any check failure as "keep
    // last known" rather than overwriting to offline.
    try {
      _lastConnectivity = await _connectivity.checkConnectivity();
    } catch (_) {
      // ignore — fall back to the previous value
    }

    final l1 = !_lastConnectivity.contains(ConnectivityResult.none) ||
        _lastConnectivity.length > 1;

    // A passive probe trusts connectivity_plus: if it reports no network,
    // short-circuit to offline rather than spend a doomed round-trip. A FORCED
    // probe (the user tapped "Try syncing now") does NOT trust it — as the
    // checkConnectivity note above flags, connectivity_plus reports `[none]`
    // stale on iOS after the network returns, which would otherwise leave a
    // banked-up queue permanently gated (canWriteToFirebase=false). Fall
    // through and let the authoritative L3 Firestore probe decide: it can only
    // succeed if the backend genuinely answers, so there's no false positive.
    if (!l1 && !forced) {
      final snap = _buildSnapshot(
        status: ServiceStatus.offline,
        deviceConnected: false,
        internetReachable: false,
        firebaseReachable: false,
      );
      _emit(snap);
      return snap;
    }

    // L2 (public internet HEAD) runs in parallel with L3. L3 is the
    // authoritative answer to "can we talk to the backend"; L2 is only
    // consulted when L3 fails so we can tell `offline` from `firebaseDown`.
    // Running L2 concurrently means we never block the happy path on a
    // network that quietly drops 1.1.1.1 traffic.
    //
    // First probe gets a wider L3 budget — Firestore's gRPC channel + TLS
    // handshake regularly take 3–6s on a real device cold start, well
    // inside healthy territory but past the steady-state 3s timeout.
    final l3Timeout = _coldStart ? _coldStartProbeTimeout : _probeTimeout;
    final l2Future = _http
        .head(_internetProbeUrl)
        .timeout(_probeTimeout)
        .then<bool>((resp) => resp.statusCode < 500)
        .catchError((_) => false);

    // L3 — Firestore healthcheck doc, server-source forced so we don't
    // get a stale cache hit and miss the outage.
    final l3Stopwatch = Stopwatch()..start();
    bool l3 = false;
    try {
      await _firestore
          .doc(_firebaseHealthcheckPath)
          .get(const GetOptions(source: Source.server))
          .timeout(l3Timeout);
      l3 = true;
    } on FirebaseException catch (e) {
      // `permission-denied` means Firestore answered — the user just isn't
      // authenticated yet (the healthcheck rule requires `auth != null`).
      // That's still proof the backend is reachable, so treat it as L3 OK
      // rather than flashing "Lumi service unavailable" on the splash.
      l3 = e.code == 'permission-denied';
    } catch (_) {
      l3 = false;
    }
    l3Stopwatch.stop();

    if (l3) {
      // Authoritative — Firebase responded, so we're online. Don't await
      // L2; whatever it ends up reporting can't change the verdict.
      final degraded = l3Stopwatch.elapsed > _degradedThreshold;
      final snap = _buildSnapshot(
        status: degraded ? ServiceStatus.degraded : ServiceStatus.healthy,
        deviceConnected: true,
        internetReachable: true,
        firebaseReachable: true,
        latency: l3Stopwatch.elapsed,
      );
      _emit(snap);
      return snap;
    }

    // L3 failed — fall back to L2 to disambiguate `firebaseDown` (internet
    // up, Firebase down) from a genuinely offline device.
    final l2 = await l2Future;
    final snap = _buildSnapshot(
      status: l2 ? ServiceStatus.firebaseDown : ServiceStatus.offline,
      // `l1 || l2`: a forced probe may have fallen through here with L1 false;
      // if neither connectivity_plus nor the L2 internet HEAD got through, the
      // device really is offline, so don't claim it's connected.
      deviceConnected: l1 || l2,
      internetReachable: l2,
      firebaseReachable: false,
      latency: l3Stopwatch.elapsed,
    );
    _emit(snap);
    return snap;
  }

  ServiceStatusSnapshot _buildSnapshot({
    required ServiceStatus status,
    required bool deviceConnected,
    required bool internetReachable,
    required bool firebaseReachable,
    Duration? latency,
  }) {
    return ServiceStatusSnapshot(
      status: status,
      deviceConnected: deviceConnected,
      internetReachable: internetReachable,
      firebaseReachable: firebaseReachable,
      lastProbeLatency: latency,
      checkedAt: DateTime.now(),
    );
  }

  void _emit(ServiceStatusSnapshot next) {
    // Flap / cold-start suppression: hold the first emission back until a
    // confirming probe lands. Two regimes:
    //
    //  - From `healthy` → not-healthy: suppress only when the probe layer
    //    says we're offline (`deviceConnected = true` but L2/L3 failed).
    //    If `connectivity_plus` itself flips to no-network mid-session,
    //    that's almost certainly an airplane-mode toggle — fire instantly.
    //
    //  - From the initial `unknown` state: ALWAYS suppress, even when
    //    `deviceConnected = false`. On iOS, `connectivity_plus` reports
    //    `[none]` for a beat after cold start before the wifi state has
    //    propagated; without this guard the banner flashes for 20–30s
    //    while we wait for the change listener to fire.
    //
    // Mid-session airplane toggles aren't affected: they go through
    // `_handleConnectivity`, which emits directly and resets the counter.
    // Recovery to healthy is also always immediate.
    final goingUnhealthy = next.status != ServiceStatus.healthy &&
        next.status != ServiceStatus.unknown;
    final fromHealthyAndProbeBased = _current.status == ServiceStatus.healthy &&
        next.deviceConnected;
    final fromUnknown = _current.status == ServiceStatus.unknown;
    if (goingUnhealthy && (fromHealthyAndProbeBased || fromUnknown)) {
      _consecutiveUnhealthyProbes += 1;
      if (_consecutiveUnhealthyProbes < 2) {
        // Periodic probes are 600s apart, so without intervention the user
        // waits the full interval before we get the confirming verdict —
        // long enough for a slow first probe to flash the banner. Run the
        // confirming probe within seconds instead.
        if (fromUnknown) {
          _scheduleColdStartRetry();
        }
        return;
      }
    }
    if (next.status == ServiceStatus.healthy) {
      _consecutiveUnhealthyProbes = 0;
    }

    if (_current.semanticallyEquals(next)) {
      // Keep the latency fresh for diagnostic readers but don't emit.
      _current = next;
      return;
    }
    _current = next;
    if (!_output.isClosed) _output.add(next);
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _connectivitySub?.cancel();
    _periodicTimer?.cancel();
    _debounceTimer?.cancel();
    _coldStartRetryTimer?.cancel();
    _http.close();
    await _output.close();
  }
}
