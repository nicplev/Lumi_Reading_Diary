import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../core/models/service_status.dart';
import '../core/services/service_status_controller.dart';
import '../data/models/log_comment_model.dart';
import '../data/models/reading_log_model.dart';
import '../data/models/student_model.dart';
import '../data/models/allocation_model.dart';
import 'firebase_service.dart';
import 'comprehension_audio_service.dart';

/// Local-first persistence + an outbound sync queue for writes made while
/// Firestore is unreachable.
///
/// Hardening invariants (see `fix/offline-sync-bulletproofing`):
///  - A queued write is **never silently dropped**. Transient failures back
///    off exponentially and retry forever; permanent failures are parked as
///    `needsAttention` and surfaced to the user, not deleted.
///  - Retry/backoff state is **persisted to Hive after every attempt**, so it
///    survives app restarts and mid-sync kills.
///  - The drain is gated on [ServiceStatusController.canWriteToFirebase] and
///    every Firestore call is time-bounded, so a write that would otherwise
///    hang against an L1-up / Firestore-down network can't wedge the syncer.
///  - Reading-log writes are confirmed by a **server read-back** before the
///    item leaves the queue — closing the "resolved against local cache but
///    never reached the server" silent-loss window.
class OfflineService with WidgetsBindingObserver {
  static OfflineService? _instance;
  static OfflineService get instance => _instance ??= OfflineService._();

  OfflineService._();

  // Hive boxes
  late Box<Map> _readingLogsBox;
  late Box<Map> _studentsBox;
  late Box<Map> _allocationsBox;
  late Box<Map> _pendingSyncBox;
  late Box<Map> _settingsBox;
  // Rec 5a: in-progress reading-log wizard drafts, keyed by studentId.
  late Box<Map> _logDraftsBox;
  late Box<dynamic> _serviceMetaBox;

  // Connectivity
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<ServiceStatusSnapshot>? _serviceStatusSubscription;
  bool _isOnline = true;
  ServiceStatus _lastObservedStatus = ServiceStatus.unknown;

  // Initialization flag
  bool _initialized = false;
  bool _lifecycleObserverAdded = false;

  // Sync queue
  final List<PendingSync> _syncQueue = [];
  Timer? _syncTimer;
  Timer? _retryTimer;
  bool _isSyncing = false;
  final Random _jitter = Random();

  /// Per-Firestore-call timeout. Bounds a write that would otherwise hang
  /// indefinitely when the device has connectivity but Firestore is
  /// unreachable — the failure mode that used to leave `_isSyncing` stuck.
  static const Duration _opTimeout = Duration(seconds: 30);

  /// A queued item is treated as "stale" past this age, escalating the UI
  /// even on a healthy connection.
  static const Duration staleThreshold = Duration(hours: 48);

  // ── Sync-attempt history (diagnostics) ──────────────────────────────
  static const int _historyLimit = 20;
  final List<SyncHistoryEntry> _history = [];
  final StreamController<List<SyncHistoryEntry>> _historyController =
      StreamController<List<SyncHistoryEntry>>.broadcast();

  // ── Test seams ──────────────────────────────────────────────────────
  FirebaseFirestore? _firestoreOverride;
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseService.instance.firestore;

  /// Inject a fake Firestore so specs can exercise the real drain (including
  /// receipt read-back) without a live backend. Pass `null` to reset.
  @visibleForTesting
  set firestoreForTest(FirebaseFirestore? firestore) =>
      _firestoreOverride = firestore;

  /// Reload the pending queue from Hive — lets specs prove that retry/backoff
  /// state was actually persisted (not just mutated in memory).
  @visibleForTesting
  void reloadPendingFromDiskForTest() => _loadPendingSyncs();

  /// Override the per-item network write so specs can deterministically
  /// inject failures (the fake Firestore can't simulate errors). When set,
  /// it fully replaces the real per-type sync dispatch.
  @visibleForTesting
  Future<void> Function(PendingSync item)? syncOneOverrideForTest;

  /// Override the pre-drain auth-token refresh so specs don't need a live
  /// FirebaseAuth. When set, it replaces the real forced ID-token refresh.
  @visibleForTesting
  Future<void> Function()? tokenRefreshForTest;

  Directory? _pendingAudioDirectoryOverride;

  /// Override the queue-owned audio directory so specs can exercise file
  /// preservation without relying on the platform path_provider channel.
  @visibleForTesting
  set pendingComprehensionAudioDirectoryForTest(Directory? directory) =>
      _pendingAudioDirectoryOverride = directory;

  /// Replays an allocation assignment that was queued offline. Registered at
  /// startup by IsbnAssignmentService (inverting the dependency so this
  /// infrastructure service doesn't import the feature service). The allocation
  /// upsert is a Firestore transaction with a non-trivial merge, so the drain
  /// re-runs that write rather than reimplementing it. Until registered, a
  /// queued item is treated as transient (retried), so an early-startup drain
  /// before registration doesn't park it.
  Future<void> Function(Map<String, dynamic> data)? _allocationReplay;

  void registerAllocationReplay(
    Future<void> Function(Map<String, dynamic> data) handler,
  ) {
    _allocationReplay = handler;
  }

  /// Force a fresh ID token before a drain. On cold-start the queue can drain
  /// before Firebase Auth has minted a token for the restored session; a stale
  /// token makes Firestore reject writes with a transient `permission-denied`,
  /// which we'd otherwise mis-classify as permanent and park a recoverable
  /// write. Best-effort — the caller swallows failures so the drain proceeds.
  Future<void> _refreshAuthToken() async {
    final override = tokenRefreshForTest;
    if (override != null) {
      await override();
      return;
    }
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
  }

  /// Broadcasts the current pending queue whenever it mutates. Drives the
  /// `pendingSyncProvider` so the global banner and detail sheet update
  /// live.
  final StreamController<List<PendingSync>> _queueController =
      StreamController<List<PendingSync>>.broadcast();

  /// Broadcasts the timestamp of the most recent fully-successful drain.
  final StreamController<DateTime?> _lastSyncController =
      StreamController<DateTime?>.broadcast();

  // Getters
  bool get isOnline => _isOnline;
  List<PendingSync> get pendingSyncs => List.unmodifiable(_syncQueue);
  Stream<List<PendingSync>> get queueStream => _queueController.stream;
  Stream<DateTime?> get lastSyncStream => _lastSyncController.stream;
  List<SyncHistoryEntry> get syncHistory => List.unmodifiable(_history);
  Stream<List<SyncHistoryEntry>> get historyStream => _historyController.stream;
  DateTime? get lastSuccessfulSyncAt {
    if (!_initialized) return null;
    final raw = _serviceMetaBox.get('lastSuccessfulSyncAt');
    return raw is String ? DateTime.tryParse(raw) : null;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      // Open Hive boxes
      _readingLogsBox = await Hive.openBox<Map>('reading_logs');
      _studentsBox = await Hive.openBox<Map>('students');
      _allocationsBox = await Hive.openBox<Map>('allocations');
      _pendingSyncBox = await Hive.openBox<Map>('pending_sync');
      _settingsBox = await Hive.openBox<Map>('settings');
      _logDraftsBox = await Hive.openBox<Map>('log_drafts');
      _serviceMetaBox = await Hive.openBox<dynamic>('service_meta');

      // Load pending syncs + diagnostic history
      _loadPendingSyncs();
      _loadHistory();

      // Check initial connectivity
      await _checkConnectivity();

      // Listen to connectivity changes
      _connectivitySubscription =
          _connectivity.onConnectivityChanged.listen(_handleConnectivityChange);

      // Listen to layered status — covers the Firebase-recovered case
      // where device connectivity hasn't changed but Firestore is reachable
      // again. The sync is coalesced via `_isSyncing` so the connectivity
      // trigger and this one can't fire concurrently.
      _serviceStatusSubscription =
          ServiceStatusController.instance.stream.listen(_handleServiceStatus);

      // Drain on app resume ("grandma reopens the app") even when the
      // connection never changed and was already healthy.
      if (!_lifecycleObserverAdded) {
        WidgetsBinding.instance.addObserver(this);
        _lifecycleObserverAdded = true;
      }

      // Start sync timer + any pending backoff wake-up.
      _startSyncTimer();
      _scheduleNextRetry();

      _initialized = true;
      debugPrint('Offline service initialized (${_syncQueue.length} pending)');
    } catch (e) {
      debugPrint('Error initializing offline service: $e');
      rethrow;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_resumeSync());
    }
  }

  /// On resume: re-probe so `canWriteToFirebase` is fresh, then drain. A
  /// transition to healthy also drains via [_handleServiceStatus], but that
  /// path is a no-op when we were *already* healthy — hence the explicit
  /// trigger here.
  Future<void> _resumeSync() async {
    try {
      await ServiceStatusController.instance.forceProbe();
    } catch (_) {
      // ignore — fall through to a best-effort drain
    }
    await _syncPendingData();
  }

  // Clear all cached data (call on logout)
  Future<void> clearAllCaches() async {
    if (!_initialized) {
      debugPrint('Offline service not initialized, skipping cache clear');
      return;
    }
    try {
      await _readingLogsBox.clear();
      await _studentsBox.clear();
      await _allocationsBox.clear();
      await _pendingSyncBox.clear();
      await _settingsBox.clear();
      await _logDraftsBox.clear();
      await _deleteAllQueuedComprehensionAudioFiles();
      await _clearPendingComprehensionAudioDirectory();
      _syncQueue.clear();
      _retryTimer?.cancel();
      await _clearHistory();
      _broadcastQueue();
      debugPrint('All offline caches cleared');
    } catch (e) {
      debugPrint('Error clearing offline caches: $e');
    }
  }

  /// Troubleshooting reset: clears the local *mirror* of cloud data (reading
  /// logs, students, allocations) so the app re-downloads it fresh. Crucially
  /// it preserves the pending-sync queue and local drafts, so any unsynced work
  /// is never lost — it will still upload on the next sync.
  Future<void> clearCachedData() async {
    if (!_initialized) {
      debugPrint('Offline service not initialized, skipping cached-data clear');
      return;
    }
    try {
      await _readingLogsBox.clear();
      await _studentsBox.clear();
      await _allocationsBox.clear();
      debugPrint(
          'Cleared cached cloud data (kept ${_syncQueue.length} pending writes + drafts)');
    } catch (e) {
      debugPrint('Error clearing cached data: $e');
    }
  }

  Future<void> _checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _isOnline = !results.contains(ConnectivityResult.none);

      if (_isOnline) {
        // Trigger sync when coming online
        _syncPendingData();
      }
    } catch (e) {
      debugPrint('Error checking connectivity: $e');
      _isOnline = false;
    }
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final wasOffline = !_isOnline;
    _isOnline = !results.contains(ConnectivityResult.none);

    if (wasOffline && _isOnline) {
      debugPrint('Device came online, syncing pending data...');
      _syncPendingData();
    }
  }

  void _handleServiceStatus(ServiceStatusSnapshot snapshot) {
    final wasUnhealthy = _lastObservedStatus != ServiceStatus.healthy;
    _lastObservedStatus = snapshot.status;
    if (wasUnhealthy && snapshot.status == ServiceStatus.healthy) {
      debugPrint('Firebase reachable again, draining pending queue...');
      unawaited(_syncPendingData());
    }
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_syncQueue.isNotEmpty) {
        _syncPendingData();
      }
    });
  }

  /// One-shot wake for the soonest backed-off item, so exponential backoff
  /// actually fires without waiting on the 5-minute timer or a connectivity
  /// event.
  void _scheduleNextRetry() {
    _retryTimer?.cancel();
    DateTime? soonest;
    for (final it in _syncQueue) {
      if (it.needsAttention) continue;
      final t = it.nextAttemptAt;
      if (t == null) continue;
      if (soonest == null || t.isBefore(soonest)) soonest = t;
    }
    if (soonest == null) return;
    final delay = soonest.difference(DateTime.now());
    final wait = delay.isNegative
        ? const Duration(seconds: 1)
        : delay + const Duration(milliseconds: 250);
    _retryTimer = Timer(wait, () => unawaited(_syncPendingData()));
  }

  void _loadPendingSyncs() {
    _syncQueue.clear();
    for (final key in _pendingSyncBox.keys) {
      final data = _pendingSyncBox.get(key) as Map;
      _syncQueue.add(PendingSync.fromMap(Map<String, dynamic>.from(data)));
    }
    _broadcastQueue();
  }

  void _broadcastQueue() {
    if (_queueController.isClosed) return;
    _queueController.add(List.unmodifiable(_syncQueue));
  }

  /// Externally callable sync trigger — used by the "Try syncing now"
  /// buttons. Coalesces with an in-flight sync.
  ///
  /// Automatic drains respect backoff and leave parked items alone. An
  /// explicit user retry may make one fresh attempt at every queued item,
  /// which is useful after connectivity, sign-in or school access recovers.
  /// A still-invalid write remains queued under the normal failure classifier
  /// and is never discarded.
  Future<void> triggerSync({bool retryPendingNow = false}) =>
      _syncPendingData(retryPendingNow: retryPendingNow);

  /// Manually drop a parked item the user has acknowledged. The only path by
  /// which a queued write ever leaves the queue without syncing.
  Future<void> dismissPending(String id) async {
    final removed = _syncQueue.where((it) => it.id == id).toList();
    for (final item in removed) {
      await _deleteQueuedComprehensionAudioFile(item);
    }
    _syncQueue.removeWhere((it) => it.id == id);
    if (_initialized) await _pendingSyncBox.delete(id);
    _broadcastQueue();
  }

  Future<void> _enqueueAndPersist(PendingSync sync) async {
    // Stamp an integrity hash at enqueue time. Best-effort: a payload that
    // isn't JSON-encodable simply goes unhashed rather than failing the write.
    try {
      sync.contentHash ??= PendingSync.computeContentHash(sync.data);
    } catch (_) {
      // leave contentHash null — integrity check will be skipped for this item
    }
    await _pendingSyncBox.put(sync.id, sync.toMap());
    _syncQueue.add(sync);
    _broadcastQueue();
    // A fresh item is immediately eligible; nudge a drain in case we're
    // already online and idle.
    _scheduleNextRetry();
    // Something just got queued — usually because a direct write failed or
    // the status gate said "not writable". Either way the service status is
    // the thing that decides when this queue drains, so make sure it's
    // fresh rather than waiting out the slow periodic heartbeat. Coalesced
    // by the controller's min-probe interval; fire-and-forget.
    unawaited(ServiceStatusController.instance
        .forceProbe()
        .catchError((Object _) => ServiceStatusController.instance.current));
  }

  Future<void> _persistItem(PendingSync item) async {
    if (!_initialized) return;
    await _pendingSyncBox.put(item.id, item.toMap());
  }

  /// Save reading log locally AND queue it for sync. Callers only invoke
  /// this from the offline-fallback path, so queuing is unconditional —
  /// `_isOnline` (a pure connectivity check) is too narrow now that
  /// `ServiceStatusController.canWriteToFirebase` also covers
  /// `firebaseDown` and `degraded`.
  Future<void> saveReadingLogLocally(
    ReadingLogModel log, {
    bool claimQuickSlot = false,
  }) async {
    try {
      await _readingLogsBox.put(log.id, log.toLocal());
      // The slot claim rides in the payload so the drain can replay the same
      // atomic batch (log + slot) the online path uses. fromLocal() ignores
      // the extra key.
      final data = log.toLocal();
      if (claimQuickSlot) data[quickSlotClaimKey] = true;
      await _enqueueAndPersist(PendingSync(
        id: log.id,
        type: SyncType.readingLog,
        action: SyncAction.create,
        data: data,
        createdAt: DateTime.now(),
      ));
    } catch (e) {
      debugPrint('Error saving reading log locally: $e');
      rethrow;
    }
  }

  /// Queues a delete of the caller's own reading log (undo / remove-my-
  /// session while offline) and removes the local copy so the UI reflects
  /// the removal immediately. The server-side onReadingLogDeleted cascade
  /// cleans dependents and frees the quick slot once the delete lands.
  Future<void> enqueueReadingLogDelete(ReadingLogModel log) async {
    await _readingLogsBox.delete(log.id);
    // An unsynced queued CREATE for the same id cancels out entirely —
    // nothing ever reached the server, so drop both sides locally.
    final queuedCreate = _syncQueue
        .where((it) =>
            it.id == log.id &&
            it.type == SyncType.readingLog &&
            it.action == SyncAction.create)
        .toList();
    if (queuedCreate.isNotEmpty) {
      _syncQueue.removeWhere((it) => it.id == log.id);
      await _pendingSyncBox.delete(log.id);
      _broadcastQueue();
      return;
    }
    await _enqueueAndPersist(PendingSync(
      id: log.id,
      type: SyncType.readingLog,
      action: SyncAction.delete,
      data: log.toLocal(),
      createdAt: DateTime.now(),
    ));
  }

  /// Removes the locally-cached copy of a log (after a confirmed online
  /// delete).
  Future<void> removeLocalReadingLog(String logId) async {
    if (!_initialized) return;
    await _readingLogsBox.delete(logId);
  }

  /// Queue a parent-comment attach. The log itself may already exist in
  /// Firestore (online when logged, comment added offline) or also be
  /// queued (both offline) — the drain sorts so the log creates first.
  Future<void> enqueueParentComment({
    required String logId,
    required String schoolId,
    required List<String> selections,
    required String? freeText,
    required String composedComment,
  }) async {
    final sync = PendingSync(
      id: 'comment_$logId',
      type: SyncType.parentComment,
      action: SyncAction.update,
      data: {
        'logId': logId,
        'schoolId': schoolId,
        'selections': selections,
        'freeText': freeText,
        'composedComment': composedComment,
      },
      createdAt: DateTime.now(),
    );
    await _enqueueAndPersist(sync);
  }

  /// Queue the child's feeling for a log that couldn't be patched online. Keyed
  /// by logId so re-picking a feeling supersedes the last queued one.
  Future<void> enqueueChildFeeling({
    required String logId,
    required String schoolId,
    required String feeling,
  }) async {
    final sync = PendingSync(
      id: 'feeling_$logId',
      type: SyncType.childFeeling,
      action: SyncAction.update,
      data: {
        'logId': logId,
        'schoolId': schoolId,
        'feeling': feeling,
      },
      createdAt: DateTime.now(),
    );
    await _enqueueAndPersist(sync);
  }

  /// Queue an ISBN-scan allocation write that couldn't run online (the upsert
  /// is a Firestore transaction, which can't run from cache). [books] are
  /// already serialised (ScannedIsbnBook.toMap) so this service stays
  /// dependency-free of the feature layer. Keyed per (student, week, session)
  /// so re-scans in the same session supersede rather than stack.
  Future<void> enqueueAllocationAssignment({
    required String schoolId,
    required String classId,
    required String studentId,
    required String teacherId,
    required List<Map<String, dynamic>> books,
    required int targetMinutes,
    String? sessionId,
    int? targetDateMs,
    List<String> renewedIsbns = const <String>[],
    String? demoGenerationId,
  }) async {
    final sessionKey = (sessionId != null && sessionId.isNotEmpty)
        ? sessionId
        : (targetDateMs?.toString() ?? 'now');
    final generationKey = demoGenerationId == null
        ? ''
        : '_${demoGenerationId.substring(0, min(demoGenerationId.length, 12))}';
    final sync = PendingSync(
      id: 'alloc_${studentId}_$sessionKey$generationKey',
      type: SyncType.allocationAssignment,
      action: SyncAction.update,
      data: {
        'schoolId': schoolId,
        'classId': classId,
        'studentId': studentId,
        'teacherId': teacherId,
        'books': books,
        'targetMinutes': targetMinutes,
        'sessionId': sessionId,
        'targetDateMs': targetDateMs,
        'renewedIsbns': renewedIsbns,
        'demoGenerationId': demoGenerationId,
      },
      createdAt: DateTime.now(),
    );
    await _enqueueAndPersist(sync);
  }

  /// Queue a comprehension-audio upload composed offline (or that failed
  /// online and is falling back to the queue). The handler reads the file
  /// from [localFilePath], pushes it to [storagePath], then patches the
  /// reading log doc to flip `comprehensionAudioUploaded: true`. Dependency
  /// on the log create is handled by the drain ordering in [_syncPriority].
  Future<void> enqueueComprehensionAudioUpload({
    required String logId,
    required String schoolId,
    required String studentId,
    required String storagePath,
    required String localFilePath,
    required int durationSec,
  }) async {
    final createdAt = DateTime.now();
    final data = <String, dynamic>{
      'logId': logId,
      'schoolId': schoolId,
      'studentId': studentId,
      'storagePath': storagePath,
      'localFilePath': localFilePath,
      'originalLocalFilePath': localFilePath,
      'durationSec': durationSec,
      'audioFileManagedByQueue': false,
    };

    var needsAttention = false;
    String? lastError;
    try {
      data['localFilePath'] = await _copyComprehensionAudioIntoQueue(
        logId: logId,
        localFilePath: localFilePath,
      );
      data['audioFileManagedByQueue'] = true;
    } on ComprehensionAudioMissingException catch (e) {
      // There is nothing recoverable to upload, but preserve a parked queue
      // item so the parent sees that the recording did not sync.
      needsAttention = true;
      lastError = _describeError(e);
    }

    final sync = PendingSync(
      id: 'audio_$logId',
      type: SyncType.comprehensionAudioUpload,
      action: SyncAction.create,
      data: data,
      createdAt: createdAt,
      lastAttemptAt: needsAttention ? createdAt : null,
      lastError: lastError,
      needsAttention: needsAttention,
    );
    await _replaceComprehensionAudioSync(sync);
  }

  Future<Directory> _pendingComprehensionAudioDirectory() async {
    final override = _pendingAudioDirectoryOverride;
    if (override != null) {
      if (!await override.exists()) await override.create(recursive: true);
      return override;
    }
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(
      '${supportDir.path}${Platform.pathSeparator}pending_comprehension_audio',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<String> _copyComprehensionAudioIntoQueue({
    required String logId,
    required String localFilePath,
  }) async {
    final source = File(localFilePath);
    if (!await source.exists()) {
      throw const ComprehensionAudioMissingException();
    }

    final dir = await _pendingComprehensionAudioDirectory();
    final safeLogId = _safeFilePart(logId);
    final filename =
        'audio_${safeLogId}_${DateTime.now().microsecondsSinceEpoch}.m4a';
    final destination = File('${dir.path}${Platform.pathSeparator}$filename');
    await source.copy(destination.path);
    return destination.path;
  }

  @visibleForTesting
  Future<String> copyComprehensionAudioIntoQueueForTest({
    required String logId,
    required String localFilePath,
  }) =>
      _copyComprehensionAudioIntoQueue(
        logId: logId,
        localFilePath: localFilePath,
      );

  Future<void> _replaceComprehensionAudioSync(PendingSync sync) async {
    final existing = _syncQueue.where((it) => it.id == sync.id).toList();
    for (final item in existing) {
      await _deleteQueuedComprehensionAudioFile(item);
    }
    _syncQueue.removeWhere((it) => it.id == sync.id);
    if (_initialized) await _pendingSyncBox.delete(sync.id);
    await _enqueueAndPersist(sync);
  }

  Future<void> _deleteQueuedComprehensionAudioFile(PendingSync item) async {
    if (item.type != SyncType.comprehensionAudioUpload) return;
    if (item.data['audioFileManagedByQueue'] != true) return;
    final path = item.data['localFilePath'] as String?;
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('[CompAudioSync] failed to delete queued audio copy: $e');
    }
  }

  Future<void> _deleteAllQueuedComprehensionAudioFiles() async {
    for (final item in List<PendingSync>.from(_syncQueue)) {
      await _deleteQueuedComprehensionAudioFile(item);
    }
  }

  Future<void> _clearPendingComprehensionAudioDirectory() async {
    try {
      final dir = await _pendingComprehensionAudioDirectory();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('[CompAudioSync] failed to clear pending audio directory: $e');
    }
  }

  String _safeFilePart(String value) {
    final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.isEmpty ? 'log' : safe;
  }

  /// Queue a comment-thread reply composed offline. Keyed by `commentId` so
  /// each reply is a distinct queue item (unlike the single `parentComment`
  /// per log). Replays as a batch: the comment doc plus the log's denormalized
  /// "last comment" preview, drained after the log's own create.
  Future<void> enqueueCommentReply({
    required String logId,
    required String schoolId,
    required String commentId,
    required String authorId,
    required String authorRole,
    required String authorName,
    required String body,
    required String studentId,
    required String parentId,
  }) async {
    final sync = PendingSync(
      id: 'reply_$commentId',
      type: SyncType.commentReply,
      action: SyncAction.create,
      data: {
        'logId': logId,
        'schoolId': schoolId,
        'commentId': commentId,
        'authorId': authorId,
        'authorRole': authorRole,
        'authorName': authorName,
        'body': body,
        'studentId': studentId,
        'parentId': parentId,
        'createdAt': DateTime.now().toIso8601String(),
      },
      createdAt: DateTime.now(),
    );
    await _enqueueAndPersist(sync);
  }

  /// Queue a parent-preferences update. Dedupes — multiple offline edits
  /// to the same parent collapse to the latest values.
  Future<void> enqueueParentPrefs({
    required String parentId,
    required String schoolId,
    required Map<String, dynamic> preferences,
  }) async {
    final syncId = 'prefs_$parentId';
    final existing = _syncQueue
        .indexWhere((p) => p.id == syncId && p.type == SyncType.parentPrefs);
    if (existing >= 0) {
      _syncQueue.removeAt(existing);
      await _pendingSyncBox.delete(syncId);
    }
    final sync = PendingSync(
      id: syncId,
      type: SyncType.parentPrefs,
      action: SyncAction.update,
      data: {
        'parentId': parentId,
        'schoolId': schoolId,
        'preferences': preferences,
      },
      createdAt: DateTime.now(),
    );
    await _enqueueAndPersist(sync);
  }

  // Get local reading logs
  Future<List<ReadingLogModel>> getLocalReadingLogs(String studentId) async {
    try {
      final logs = <ReadingLogModel>[];

      for (final key in _readingLogsBox.keys) {
        final data = _readingLogsBox.get(key) as Map;
        final log = ReadingLogModel.fromLocal(Map<String, dynamic>.from(data));

        if (log.studentId == studentId) {
          logs.add(log);
        }
      }

      logs.sort((a, b) => b.date.compareTo(a.date));
      return logs;
    } catch (e) {
      debugPrint('Error getting local reading logs: $e');
      return [];
    }
  }

  // ─── Reading-log wizard drafts (Rec 5a) ────────────────────────────
  // One draft per studentId, so a wizard interrupted mid-flow can be
  // restored. Saved on app background; cleared on a successful log.

  Future<void> saveLogDraft(
    String studentId,
    Map<String, dynamic> draft,
  ) async {
    if (!_initialized) return;
    try {
      await _logDraftsBox.put(studentId, draft);
    } catch (e) {
      debugPrint('Error saving log draft: $e');
    }
  }

  Map<String, dynamic>? getLogDraft(String studentId) {
    if (!_initialized) return null;
    try {
      final data = _logDraftsBox.get(studentId);
      return data != null ? Map<String, dynamic>.from(data) : null;
    } catch (e) {
      debugPrint('Error reading log draft: $e');
      return null;
    }
  }

  Future<void> clearLogDraft(String studentId) async {
    if (!_initialized) return;
    try {
      await _logDraftsBox.delete(studentId);
    } catch (e) {
      debugPrint('Error clearing log draft: $e');
    }
  }

  // Save student data locally
  Future<void> saveStudentLocally(StudentModel student) async {
    try {
      await _studentsBox.put(student.id, student.toFirestore());
    } catch (e) {
      debugPrint('Error saving student locally: $e');
      rethrow;
    }
  }

  // Get local student data
  Future<StudentModel?> getLocalStudent(String studentId) async {
    try {
      // StudentModel expects a DocumentSnapshot, so reconstructing it from a
      // plain Hive Map isn't wired up yet — fall back to online data.
      return null;
    } catch (e) {
      debugPrint('Error getting local student: $e');
      return null;
    }
  }

  // Save allocation locally
  Future<void> saveAllocationLocally(AllocationModel allocation) async {
    try {
      await _allocationsBox.put(allocation.id, allocation.toFirestore());
    } catch (e) {
      debugPrint('Error saving allocation locally: $e');
      rethrow;
    }
  }

  // Get local allocations
  Future<List<AllocationModel>> getLocalAllocations(String classId) async {
    try {
      final allocations = <AllocationModel>[];

      for (final key in _allocationsBox.keys) {
        final data = _allocationsBox.get(key);
        if (data != null && data['classId'] == classId) {
          // Create allocation from data
          // Similar issue with DocumentSnapshot
        }
      }

      return allocations;
    } catch (e) {
      debugPrint('Error getting local allocations: $e');
      return [];
    }
  }

  /// Drain the pending queue.
  ///
  /// Coalesced by `_isSyncing`, gated on a healthy write path, and wrapped in
  /// try/finally so a timeout can never leave the syncer wedged. Items are
  /// removed only after a confirmed write; failures persist their backoff
  /// state and stay queued (transient) or are parked (permanent).
  Future<void> _syncPendingData({bool retryPendingNow = false}) async {
    if (_isSyncing || _syncQueue.isEmpty) return;
    if (!ServiceStatusController.instance.current.canWriteToFirebase) {
      debugPrint(
        '[OfflineSync] drain gated by canWriteToFirebase=false; '
        'pending=${_syncQueue.length}',
      );
      return;
    }
    if (retryPendingNow) {
      // Only clear backoff/attention after the authoritative write-path probe
      // is healthy. Otherwise an offline button tap could change queue state
      // without making an attempt or scheduling a later retry.
      for (final item in _syncQueue) {
        item
          ..needsAttention = false
          ..nextAttemptAt = null
          ..lastError = null;
        await _persistItem(item);
      }
      _broadcastQueue();
    }
    debugPrint(
      '[OfflineSync] drain starting; pending=${_syncQueue.length}',
    );

    _isSyncing = true;
    _broadcastQueue();

    // Refresh the auth token before touching the backend so a cold-start stale
    // token can't make Firestore reject writes with a transient
    // `permission-denied`. Non-fatal — a failure here (offline, no user) must
    // not block the drain; genuine per-item errors still classify correctly.
    try {
      await _refreshAuthToken();
    } catch (e) {
      debugPrint(
          '[OfflineSync] pre-drain token refresh failed (non-fatal): $e');
    }

    final syncedItems = <String>[];
    var anySuccess = false;
    var anyFailure = false;

    try {
      // Drain in priority order: reading-log creates first (so dependent
      // comment writes have a doc to target), then comments, then prefs.
      final ordered = List<PendingSync>.from(_syncQueue)
        ..sort(
            (a, b) => _syncPriority(a.type).compareTo(_syncPriority(b.type)));

      for (final item in ordered) {
        // Skip parked items and items still inside their backoff window.
        if (item.needsAttention) continue;
        final nextAt = item.nextAttemptAt;
        if (nextAt != null && nextAt.isAfter(DateTime.now())) continue;

        // Integrity: a stored hash that no longer matches the payload means
        // the persisted data was corrupted — quarantine rather than sync it.
        final expected = item.contentHash;
        if (expected != null &&
            expected != PendingSync.computeContentHash(item.data)) {
          item
            ..needsAttention = true
            ..lastError = 'Integrity check failed'
            ..lastAttemptAt = DateTime.now();
          await _persistItem(item);
          _recordHistory(item, SyncResult.integrityFail, item.lastError);
          continue;
        }
        // Back-fill a hash for items queued before checksums shipped, so
        // future corruption becomes detectable.
        item.contentHash ??= PendingSync.computeContentHash(item.data);

        try {
          await _syncOne(item).timeout(_opTimeoutFor(item.type));
          syncedItems.add(item.id);
          anySuccess = true;
          _recordHistory(item, SyncResult.success, null);
        } catch (e) {
          await _handleItemFailure(item, e);
          anyFailure = true;
        }
      }

      // Remove only confirmed items from queue and storage.
      for (final id in syncedItems) {
        final removed = _syncQueue.where((it) => it.id == id).toList();
        for (final item in removed) {
          await _deleteQueuedComprehensionAudioFile(item);
        }
        _syncQueue.removeWhere((it) => it.id == id);
        await _pendingSyncBox.delete(id);
      }

      if (anySuccess) {
        final ts = DateTime.now();
        await _serviceMetaBox.put('lastSuccessfulSyncAt', ts.toIso8601String());
        if (!_lastSyncController.isClosed) _lastSyncController.add(ts);
      }

      // Drain hit failures: the backend may have just gone unhealthy — make
      // the status controller re-check now instead of waiting out its slow
      // periodic heartbeat (coalesced by its min-probe interval).
      if (anyFailure) {
        unawaited(ServiceStatusController.instance.forceProbe().catchError(
            (Object _) => ServiceStatusController.instance.current));
      }
    } finally {
      _isSyncing = false;
      _broadcastQueue();
      _scheduleNextRetry();
      debugPrint('Sync pass complete. Remaining items: ${_syncQueue.length}');
    }
  }

  /// Classify a failure and update the item's persisted retry/backoff state.
  /// Never drops the item.
  Future<void> _handleItemFailure(PendingSync item, Object error) async {
    // A quick-slot conflict is not a failure to retry — it's a decision only
    // the guardian can make ("Same session — discard mine" / "Different
    // session — add mine"). Park it with the winner's details so the UI can
    // present the choice; resolveQuickSlotConflict() re-arms or drops it.
    if (error is QuickSlotConflictException) {
      item
        ..retryCount += 1
        ..lastAttemptAt = DateTime.now()
        ..lastError = quickSlotConflictError
        ..needsAttention = true;
      item.data[quickSlotConflictKey] = {
        'occurredOn': error.occurredOn,
        if (error.byUid != null) 'byUid': error.byUid,
        if (error.existingLogId != null) 'existingLogId': error.existingLogId,
      };
      item.contentHash = PendingSync.computeContentHash(item.data);
      await _persistItem(item);
      _recordHistory(item, SyncResult.permanentFail, item.lastError);
      _broadcastQueue();
      return;
    }

    item
      ..retryCount += 1
      ..lastAttemptAt = DateTime.now()
      ..lastError = _describeError(error);

    if (_isPermanent(error, item.retryCount)) {
      // Won't succeed on retry (auth/rules/validation). Park it for the user
      // rather than dropping it or hammering the backend forever.
      item.needsAttention = true;
      _recordHistory(item, SyncResult.permanentFail, item.lastError);
      debugPrint('Permanent sync failure for ${item.id}: ${item.lastError}');
    } else {
      item.nextAttemptAt = item.lastAttemptAt!
          .add(PendingSync.backoffFor(item.retryCount, _jitter));
      _recordHistory(item, SyncResult.transientFail, item.lastError);
      debugPrint(
          'Transient sync failure for ${item.id} (attempt ${item.retryCount}); '
          'next try ${item.nextAttemptAt}');
    }
    // Persist the updated state so backoff/attention survives a restart —
    // the bug that previously made retry counting incoherent.
    await _persistItem(item);
  }

  /// Pending quick logs parked on a slot conflict, for the reconnect prompt
  /// ("{name} logged reading while you were offline. Was yours the same
  /// session?"). Each item's `data[quickSlotConflictKey]` carries the
  /// winner's details.
  List<PendingSync> get quickSlotConflicts => _syncQueue
      .where((it) =>
          it.type == SyncType.readingLog &&
          it.lastError == quickSlotConflictError &&
          it.data[quickSlotConflictKey] != null)
      .toList(growable: false);

  /// Resolves a parked quick-slot conflict.
  ///
  /// [keepMine] = "Different session — add mine": the claim is stripped so
  /// the drain replays it as a plain additional session (never touching the
  /// winner's slot). Otherwise ("Same session — discard mine") the item and
  /// its local optimistic copy are dropped — nothing was ever written.
  Future<void> resolveQuickSlotConflict({
    required String logId,
    required bool keepMine,
  }) async {
    final matches = _syncQueue
        .where((it) => it.id == logId && it.type == SyncType.readingLog)
        .toList();
    if (matches.isEmpty) return;
    final item = matches.first;
    if (!keepMine) {
      _syncQueue.removeWhere((it) => it.id == logId);
      await _pendingSyncBox.delete(logId);
      await _readingLogsBox.delete(logId);
      _broadcastQueue();
      return;
    }
    item.data.remove(quickSlotClaimKey);
    item.data.remove(quickSlotConflictKey);
    item
      ..needsAttention = false
      ..nextAttemptAt = null
      ..lastError = null
      ..contentHash = PendingSync.computeContentHash(item.data);
    await _persistItem(item);
    _broadcastQueue();
    unawaited(triggerSync());
  }

  /// Purges every locally-cached artefact for one child — called on child
  /// unlink and access revocation so child-scoped data (and queued writes
  /// that would now be rules-rejected anyway) never outlives the
  /// relationship. Sign-out uses [clearAllCaches].
  Future<void> purgeChildData(String studentId) async {
    if (!_initialized) return;
    final logKeys = _readingLogsBox.keys.where((key) {
      final raw = _readingLogsBox.get(key);
      return raw != null && raw['studentId'] == studentId;
    }).toList();
    for (final key in logKeys) {
      await _readingLogsBox.delete(key);
    }
    await _logDraftsBox.delete(studentId);
    await _studentsBox.delete(studentId);
    final queued = _syncQueue
        .where((it) => it.data['studentId'] == studentId)
        .map((it) => it.id)
        .toList();
    for (final id in queued) {
      _syncQueue.removeWhere((it) => it.id == id);
      await _pendingSyncBox.delete(id);
    }
    if (queued.isNotEmpty) _broadcastQueue();
  }

  Future<void> _syncOne(PendingSync item) async {
    final override = syncOneOverrideForTest;
    if (override != null) {
      await override(item);
      return;
    }
    switch (item.type) {
      case SyncType.readingLog:
        await _syncReadingLog(item);
        break;
      case SyncType.comprehensionAudioUpload:
        await _syncComprehensionAudioUpload(item);
        break;
      case SyncType.student:
        await _syncStudent(item);
        break;
      case SyncType.allocation:
        await _syncAllocation(item);
        break;
      case SyncType.parentComment:
        await _syncParentComment(item);
        break;
      case SyncType.commentReply:
        await _syncCommentReply(item);
        break;
      case SyncType.parentPrefs:
        await _syncParentPrefs(item);
        break;
      case SyncType.childFeeling:
        await _syncChildFeeling(item);
        break;
      case SyncType.allocationAssignment:
        await _syncAllocationAssignment(item);
        break;
    }
  }

  /// Lower number → drained earlier. Reading-log creates must precede any
  /// parent-comment updates and audio uploads that target the same log.
  int _syncPriority(SyncType type) {
    switch (type) {
      case SyncType.readingLog:
        return 0;
      case SyncType.comprehensionAudioUpload:
        return 1;
      case SyncType.parentComment:
        return 2;
      case SyncType.childFeeling:
        return 2;
      case SyncType.commentReply:
        return 3;
      case SyncType.student:
        return 4;
      case SyncType.allocation:
        return 5;
      case SyncType.parentPrefs:
        return 6;
      case SyncType.allocationAssignment:
        return 5;
    }
  }

  /// Per-type timeout. Audio uploads can take longer than the default 30s
  /// on slow uplinks (~480KB file), so they get a 90s ceiling. Everything
  /// else uses [_opTimeout].
  Duration _opTimeoutFor(SyncType type) =>
      type == SyncType.comprehensionAudioUpload
          ? const Duration(seconds: 90)
          : _opTimeout;

  Future<void> _syncReadingLog(PendingSync pendingSync) async {
    final log = ReadingLogModel.fromLocal(pendingSync.data);

    final schoolId = pendingSync.data['schoolId'] as String?;
    if (schoolId == null) {
      throw Exception('Missing schoolId for reading log sync');
    }

    final logRef = _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('readingLogs')
        .doc(log.id);

    var resolvedConflict = false;
    switch (pendingSync.action) {
      case SyncAction.create:
      case SyncAction.update:
        {
          // Existence check for conflict resolution. For an offline-created log
          // the doc doesn't exist on the server yet, and a PARENT's get() on a
          // missing readingLog is DENIED by the rules (they dereference
          // `resource.data`, which is null for a missing doc → permission-denied,
          // NOT a clean not-found). Treat a denied/not-found pre-check as "does
          // not exist yet" and fall through to the create — which the parent IS
          // allowed to do (linked + live access + parentId == uid). A genuine
          // permission problem resurfaces on the set() below.
          DocumentSnapshot<Map<String, dynamic>>? existingDoc;
          try {
            existingDoc = await logRef.get();
          } on FirebaseException catch (e) {
            if (e.code != 'permission-denied' && e.code != 'not-found') {
              rethrow;
            }
            existingDoc = null;
          }
          if (existingDoc != null && existingDoc.exists) {
            // The random log ID is the idempotency key. If that ID already
            // exists, the server copy is authoritative: a retry is a receipt,
            // while an astronomically unlikely collision must never overwrite
            // another parent's/teacher's accepted record.
            await _resolveReadingLogConflict(log, existingDoc);
            resolvedConflict = true;
          } else {
            final createData = log.toFirestore();
            createData['createdAt'] = FieldValue.serverTimestamp();
            createData.remove('comprehensionAudioPath');
            createData.remove('comprehensionAudioDurationSec');
            createData.remove('comprehensionAudioUploaded');
            createData.remove('comprehensionAudioUploadedAt');
            createData.remove('comprehensionAudioObjectGeneration');
            createData.remove('comprehensionQuestionText');
            createData.remove('comprehensionAudioReviewStatus');
            createData.remove('comprehensionAudioReviewedAt');
            createData.remove('comprehensionAudioReviewedGeneration');
            createData.remove('teacherComment');
            createData.remove('commentedAt');
            createData.remove('commentedBy');
            createData.remove('lastCommentPreview');
            createData.remove('lastCommentAt');
            createData.remove('lastCommentByRole');
            createData.remove('commentsViewedAt');

            final claimsSlot =
                pendingSync.data[quickSlotClaimKey] == true &&
                    log.occurredOn != null;
            if (claimsSlot) {
              // Replay the same atomic shape as the online quick log:
              // log create + slot create in ONE batch. If another guardian
              // (or this guardian's other device) claimed the day's slot
              // while we were offline, do NOT write — park the item as an
              // explicit conflict for the guardian to resolve ("Same
              // session — discard mine" / "Different session — add mine").
              final slotRef = _firestore
                  .collection('schools')
                  .doc(schoolId)
                  .collection('students')
                  .doc(log.studentId)
                  .collection('quickSlots')
                  .doc(log.occurredOn);
              Map<String, dynamic>? slotData;
              try {
                final slotSnap =
                    await slotRef.get(const GetOptions(source: Source.server));
                if (slotSnap.exists) slotData = slotSnap.data();
              } on FirebaseException catch (e) {
                if (e.code != 'permission-denied' && e.code != 'not-found') {
                  rethrow;
                }
                // Unreadable → let the batch + rules arbitrate below.
              }
              if (slotData != null && slotData['logId'] != log.id) {
                throw QuickSlotConflictException(
                  occurredOn: log.occurredOn!,
                  byUid: slotData['byUid'] as String?,
                  existingLogId: slotData['logId'] as String?,
                );
              }
              final batch = _firestore.batch();
              batch.set(logRef, createData);
              batch.set(slotRef, {
                'logId': log.id,
                'byUid': log.parentId,
                'createdAt': FieldValue.serverTimestamp(),
              });
              try {
                await batch.commit();
              } on FirebaseException catch (e) {
                if (e.code != 'permission-denied') rethrow;
                // Lost the race between check and commit → conflict, not a
                // genuine authz failure (that would also deny the re-read).
                final slotNow =
                    await slotRef.get(const GetOptions(source: Source.server));
                if (slotNow.exists && slotNow.data()?['logId'] != log.id) {
                  throw QuickSlotConflictException(
                    occurredOn: log.occurredOn!,
                    byUid: slotNow.data()?['byUid'] as String?,
                    existingLogId: slotNow.data()?['logId'] as String?,
                  );
                }
                rethrow;
              }
            } else {
              await logRef.set(createData);
            }
          }
        }
        break;
      case SyncAction.delete:
        await logRef.delete();
        // Receipt for a delete: confirm it's actually gone server-side.
        final gone = await logRef.get(const GetOptions(source: Source.server));
        if (gone.exists) {
          throw Exception('Receipt failed: log ${log.id} still present');
        }
        return;
    }

    // Receipt confirmation — read the doc back from the SERVER. This is the
    // crux of "never silently dropped": only once the server confirms the
    // write do we let the drain remove this item from the queue. A failure
    // here throws (transient) and the item is retried next cycle.
    final receipt = await logRef.get(const GetOptions(source: Source.server));
    if (!receipt.exists) {
      throw Exception(
          'Receipt failed: log ${log.id} not on server after write');
    }

    if (!resolvedConflict) {
      final syncedLog = log.copyWith(
        syncedAt: DateTime.now(),
        isOfflineCreated: false,
      );
      await _readingLogsBox.put(log.id, syncedLog.toLocal());
    }

    // No client-side stats recompute needed: writing the synced log to
    // Firestore triggers the aggregateStudentStats Cloud Function, which is
    // the single source of truth for the student's stats.
  }

  /// Replay a queued comprehension audio upload: push the local m4a to
  /// Storage, patch the log doc to flip `comprehensionAudioUploaded`, then
  /// confirm via a server-source read-back. The log create has priority 0
  /// so by the time this runs the target doc usually exists — if it
  /// doesn't yet (race or its own retry), we re-throw transient so the
  /// queue retries instead of quarantining.
  Future<void> _syncComprehensionAudioUpload(PendingSync pendingSync) async {
    final data = pendingSync.data;
    final logId = data['logId'] as String?;
    final schoolId = data['schoolId'] as String?;
    final storagePath = data['storagePath'] as String?;
    final localFilePath = data['localFilePath'] as String?;
    final durationSec = (data['durationSec'] as num?)?.toInt() ?? 0;
    final studentId = data['studentId'] as String? ?? '';

    if (logId == null ||
        schoolId == null ||
        storagePath == null ||
        localFilePath == null) {
      throw Exception('Missing fields for comprehension audio upload sync');
    }

    final expectedStoragePath =
        'comprehension_audio_uploads/$schoolId/$logId.m4a';
    if (storagePath != expectedStoragePath) {
      throw Exception('Non-canonical comprehension audio path');
    }
    final ownerUid = FirebaseAuth.instance.currentUser?.uid;
    if (ownerUid == null) {
      throw Exception('Sign in required for comprehension audio upload sync');
    }

    var file = File(localFilePath);
    if (!file.existsSync()) {
      final originalPath = data['originalLocalFilePath'] as String?;
      final originalFile = originalPath != null && originalPath != localFilePath
          ? File(originalPath)
          : null;
      if (originalFile != null && originalFile.existsSync()) {
        final queuedPath = await _copyComprehensionAudioIntoQueue(
          logId: logId,
          localFilePath: originalFile.path,
        );
        data['localFilePath'] = queuedPath;
        data['audioFileManagedByQueue'] = true;
        pendingSync.contentHash = PendingSync.computeContentHash(data);
        await _persistItem(pendingSync);
        file = File(queuedPath);
      } else {
        // Local source vanished — surface to user via needsAttention rather
        // than retry forever.
        throw const ComprehensionAudioMissingException();
      }
    }

    try {
      await FirebaseStorage.instance.ref(storagePath).putFile(
            file,
            SettableMetadata(
              contentType: 'audio/mp4',
              customMetadata: {
                'uploadedAt': DateTime.now().toUtc().toIso8601String(),
                'durationSec': '$durationSec',
                'schoolId': schoolId,
                'logId': logId,
                'ownerUid': ownerUid,
                'studentId': studentId,
                // TODO(retention): used by the future term-aware cleanup function.
              },
            ),
          );
    } catch (e) {
      debugPrint(
          '[CompAudioSync] step=storage_upload failed logId=$logId path=$storagePath '
          'type=${e.runtimeType} err=$e');
      rethrow;
    }

    final logRef = _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('readingLogs')
        .doc(logId);

    try {
      await ComprehensionAudioService().confirmUpload(
        schoolId: schoolId,
        logId: logId,
        durationSec: durationSec,
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
          '[CompAudioSync] step=server_confirm failed logId=$logId code=${e.code} msg=${e.message}');
      if (e.code == 'not-found' || e.code == 'permission-denied') {
        // The log create hasn't drained yet, so the doc doesn't exist — and a
        // parent UPDATE on a missing readingLog is DENIED by the rules
        // (permission-denied), not a clean not-found. Either way it's transient:
        // re-throw as a generic Exception so it's classified transient (retry),
        // and the patch lands once the log create drains (priority 0).
        throw Exception('Target log $logId not yet present; will retry');
      }
      rethrow;
    }

    // Receipt confirmation: read back from the SERVER so we know the flag
    // landed before removing the item from the queue.
    try {
      final receipt = await logRef.get(const GetOptions(source: Source.server));
      if (!receipt.exists ||
          receipt.data()?['comprehensionAudioUploaded'] != true) {
        debugPrint(
            '[CompAudioSync] step=receipt_readback flag not set logId=$logId '
            'exists=${receipt.exists}');
        throw Exception(
            'Receipt failed: comprehensionAudioUploaded not set on server');
      }
    } on FirebaseException catch (e) {
      debugPrint(
          '[CompAudioSync] step=receipt_readback firebase err logId=$logId code=${e.code} msg=${e.message}');
      rethrow;
    }

    // Best-effort temp cleanup — the LAST step so a failure above leaves
    // the file in place for a retry.
    try {
      await file.delete();
    } catch (_) {}
  }

  Future<void> _syncParentComment(PendingSync pendingSync) async {
    final logId = pendingSync.data['logId'] as String?;
    final schoolId = pendingSync.data['schoolId'] as String?;
    if (logId == null || schoolId == null) {
      throw Exception('Missing logId/schoolId for parent comment sync');
    }
    final selections =
        (pendingSync.data['selections'] as List?)?.cast<String>() ??
            const <String>[];
    final freeText = pendingSync.data['freeText'] as String?;
    final composed = pendingSync.data['composedComment'] as String?;

    final logRef = _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('readingLogs')
        .doc(logId);

    try {
      await logRef.update({
        'parentCommentSelections': selections,
        'parentCommentFreeText':
            (freeText != null && freeText.isNotEmpty) ? freeText : null,
        'parentComment':
            (composed != null && composed.isNotEmpty) ? composed : null,
      });
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') {
        // The target log hasn't reached the server yet (its own create may
        // still be backing off). Keep retrying rather than quarantining —
        // re-thrown as a plain Exception so it's classified transient.
        throw Exception('Target log $logId not yet present; will retry');
      }
      rethrow;
    }
  }

  /// Replay a child feeling queued offline: patch `childFeeling` onto the log.
  Future<void> _syncChildFeeling(PendingSync pendingSync) async {
    final logId = pendingSync.data['logId'] as String?;
    final schoolId = pendingSync.data['schoolId'] as String?;
    final feeling = pendingSync.data['feeling'] as String?;
    if (logId == null || schoolId == null || feeling == null) {
      throw Exception('Missing logId/schoolId/feeling for child feeling sync');
    }
    final logRef = _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('readingLogs')
        .doc(logId);
    try {
      await logRef.update({'childFeeling': feeling});
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') {
        // Target log's own create may still be draining — retry, don't park.
        throw Exception('Target log $logId not yet present; will retry');
      }
      rethrow;
    }
  }

  /// Replay a queued ISBN-scan allocation via the handler IsbnAssignmentService
  /// registered at startup (it re-runs the transaction/merge online). If no
  /// handler is registered yet (very early startup), throw so the item is kept
  /// and retried rather than parked.
  Future<void> _syncAllocationAssignment(PendingSync pendingSync) async {
    final replay = _allocationReplay;
    if (replay == null) {
      throw Exception(
          'Allocation replay handler not registered yet; will retry');
    }
    await replay(Map<String, dynamic>.from(pendingSync.data));
  }

  /// Replay a comment-thread reply composed offline: write the comment doc and
  /// refresh the log's denormalized preview in one batch, preserving the time
  /// the comment was originally written.
  Future<void> _syncCommentReply(PendingSync pendingSync) async {
    final data = pendingSync.data;
    final logId = data['logId'] as String?;
    final schoolId = data['schoolId'] as String?;
    final commentId = data['commentId'] as String?;
    if (logId == null || schoolId == null || commentId == null) {
      throw Exception(
          'Missing logId/schoolId/commentId for comment reply sync');
    }

    final roleName = data['authorRole'] as String? ?? 'parent';
    final body = data['body'] as String? ?? '';
    final logRef = _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('readingLogs')
        .doc(logId);
    final commentRef = logRef.collection('comments').doc(commentId);

    final comment = LogCommentModel(
      id: commentId,
      authorId: data['authorId'] as String? ?? '',
      authorRole: CommentAuthorRole.values.firstWhere(
        (e) => e.toString() == 'CommentAuthorRole.$roleName',
        orElse: () => CommentAuthorRole.parent,
      ),
      authorName: data['authorName'] as String? ?? '',
      body: body,
      createdAt: DateTime.now(),
      studentId: data['studentId'] as String? ?? '',
      parentId: data['parentId'] as String? ?? '',
    );

    try {
      final batch = _firestore.batch();
      batch.set(commentRef, comment.toFirestore());
      batch.update(logRef, {
        'lastCommentPreview': body,
        'lastCommentAt': FieldValue.serverTimestamp(),
        'lastCommentByRole': roleName,
      });
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') {
        // The target log hasn't reached the server yet — keep retrying rather
        // than quarantining (classified transient via a plain Exception).
        throw Exception('Target log $logId not yet present; will retry');
      }
      rethrow;
    }
  }

  Future<void> _syncParentPrefs(PendingSync pendingSync) async {
    final parentId = pendingSync.data['parentId'] as String?;
    final schoolId = pendingSync.data['schoolId'] as String?;
    final prefs = pendingSync.data['preferences'];
    if (parentId == null || schoolId == null || prefs is! Map) {
      throw Exception('Missing parentId/schoolId/preferences for prefs sync');
    }

    final parentRef = _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('parents')
        .doc(parentId);

    await parentRef.update({
      'preferences': Map<String, dynamic>.from(prefs),
    });
  }

  /// Resolve conflicts when syncing reading logs. Owns the local-copy update
  /// for the branch it takes, so callers must not overwrite the local box
  /// afterwards.
  Future<void> _resolveReadingLogConflict(
    ReadingLogModel localLog,
    dynamic remoteDoc,
  ) async {
    final remoteData = remoteDoc.data() as Map<String, dynamic>?;
    if (remoteData == null) {
      throw StateError(
        'Existing reading log ${localLog.id} had no server data; retry safely',
      );
    }

    // Explicit policy: reading logs are create-once events, not shared drafts.
    // Parent and teacher devices generate independent 128-bit IDs, so their
    // entries coexist. Field-specific later actions (feelings/comments) use
    // separate merge queues. Device clocks are therefore never used to choose
    // a winner and an offline create can never clobber accepted server data.
    debugPrint('Reading-log id already accepted; keeping server version');
    final remoteLog = ReadingLogModel.fromFirestore(remoteDoc);
    await _readingLogsBox.put(localLog.id, remoteLog.toLocal());
  }

  Future<void> _syncStudent(PendingSync pendingSync) async {
    final studentData = Map<String, dynamic>.from(pendingSync.data);
    final studentId = pendingSync.id;
    final schoolId = studentData['schoolId'] as String?;

    if (schoolId == null) {
      throw Exception('Missing schoolId for student sync');
    }

    final studentRef = _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('students')
        .doc(studentId);

    switch (pendingSync.action) {
      case SyncAction.create:
        await studentRef.set(studentData);
        break;
      case SyncAction.update:
        await studentRef.update(studentData);
        break;
      case SyncAction.delete:
        await studentRef.delete();
        break;
    }

    debugPrint('Student synced: $studentId');
  }

  Future<void> _syncAllocation(PendingSync pendingSync) async {
    final allocationData = Map<String, dynamic>.from(pendingSync.data);
    final allocationId = pendingSync.id;
    final schoolId = allocationData['schoolId'] as String?;

    if (schoolId == null) {
      throw Exception('Missing schoolId for allocation sync');
    }

    final allocationRef = _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('allocations')
        .doc(allocationId);

    switch (pendingSync.action) {
      case SyncAction.create:
        await allocationRef.set(allocationData);
        break;
      case SyncAction.update:
        await allocationRef.update(allocationData);
        break;
      case SyncAction.delete:
        await allocationRef.delete();
        break;
    }

    debugPrint('Allocation synced: $allocationId');
  }

  /// Firestore error codes that won't be fixed by retrying — the write is
  /// rejected for auth / rules / validation reasons. Everything else
  /// (`unavailable`, `deadline-exceeded`, timeouts, network) is transient.
  static const Set<String> _permanentCodes = {
    'permission-denied',
    'invalid-argument',
    'not-found',
    'failed-precondition',
    'already-exists',
    'out-of-range',
    'unimplemented',
    'data-loss',
  };

  /// `permission-denied` is normally a genuine rules/auth rejection (permanent),
  /// but a cold-start stale-token race can produce a TRANSIENT one that a fresh
  /// token fixes. Give it a few bounded retries (backoff lets the refreshed
  /// token land) before parking — so a recoverable write isn't stranded. A real
  /// denial still parks once the retries are exhausted.
  static const int _permissionDeniedRetryLimit = 3;

  bool _isPermanent(Object error, int retryCount) {
    if (error is ComprehensionAudioMissingException) return true;
    if (error is! FirebaseException) return false;
    if (error.code == 'permission-denied' &&
        retryCount < _permissionDeniedRetryLimit) {
      // Not yet — retry a bounded number of times before treating it as a real
      // denial. (Still in _permanentCodes, so it parks once the limit is hit.)
      return false;
    }
    return _permanentCodes.contains(error.code);
  }

  String _describeError(Object error) {
    if (error is FirebaseException) {
      final msg = error.message;
      return msg == null || msg.isEmpty ? error.code : '${error.code}: $msg';
    }
    if (error is ComprehensionAudioMissingException) {
      return 'The recording file is no longer available on this device.';
    }
    if (error is TimeoutException) return 'Timed out';
    return error.toString();
  }

  // ── Sync-attempt history ────────────────────────────────────────────
  void _recordHistory(PendingSync item, SyncResult result, String? error) {
    _history.add(SyncHistoryEntry(
      at: DateTime.now(),
      itemId: item.id,
      type: item.type,
      action: item.action,
      result: result,
      error: error,
    ));
    while (_history.length > _historyLimit) {
      _history.removeAt(0);
    }
    if (_initialized) {
      unawaited(_serviceMetaBox.put(
        'syncHistory',
        _history.map((e) => e.toMap()).toList(),
      ));
    }
    if (!_historyController.isClosed) {
      _historyController.add(List.unmodifiable(_history));
    }
  }

  void _loadHistory() {
    _history.clear();
    final raw = _serviceMetaBox.get('syncHistory');
    if (raw is List) {
      for (final e in raw) {
        try {
          _history.add(
              SyncHistoryEntry.fromMap(Map<String, dynamic>.from(e as Map)));
        } catch (_) {
          // skip malformed entries
        }
      }
    }
  }

  Future<void> _clearHistory() async {
    _history.clear();
    if (_initialized) await _serviceMetaBox.delete('syncHistory');
    if (!_historyController.isClosed) {
      _historyController.add(const []);
    }
  }

  // Clear all local data
  Future<void> clearLocalData() async {
    if (!_initialized) return;
    await _readingLogsBox.clear();
    await _studentsBox.clear();
    await _allocationsBox.clear();
    await _pendingSyncBox.clear();
    await _logDraftsBox.clear();
    await _deleteAllQueuedComprehensionAudioFiles();
    await _clearPendingComprehensionAudioDirectory();
    _syncQueue.clear();
    _retryTimer?.cancel();
    await _clearHistory();
    _broadcastQueue();
  }

  // Clear old data
  Future<void> clearOldData({int daysToKeep = 30}) async {
    final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));

    // Clear old reading logs
    final keysToDelete = <dynamic>[];
    for (final key in _readingLogsBox.keys) {
      final data = _readingLogsBox.get(key) as Map;
      final date = DateTime.parse(data['date']);
      if (date.isBefore(cutoffDate)) {
        keysToDelete.add(key);
      }
    }

    for (final key in keysToDelete) {
      await _readingLogsBox.delete(key);
    }

    debugPrint('Cleared ${keysToDelete.length} old reading logs');
  }

  // Get sync status
  SyncStatus getSyncStatus() {
    if (_isSyncing) {
      return SyncStatus.syncing;
    } else if (_syncQueue.isEmpty) {
      return SyncStatus.synced;
    } else if (_isOnline) {
      return SyncStatus.pending;
    } else {
      return SyncStatus.offline;
    }
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _serviceStatusSubscription?.cancel();
    _syncTimer?.cancel();
    _retryTimer?.cancel();
    if (_lifecycleObserverAdded) {
      WidgetsBinding.instance.removeObserver(this);
      _lifecycleObserverAdded = false;
    }
    if (!_queueController.isClosed) _queueController.close();
    if (!_lastSyncController.isClosed) _lastSyncController.close();
    if (!_historyController.isClosed) _historyController.close();
  }
}

// Sync models
enum SyncType {
  readingLog,
  comprehensionAudioUpload,
  student,
  allocation,
  parentComment,
  commentReply,
  parentPrefs,
  childFeeling,
  allocationAssignment,
}

/// Extra key in a queued reading-log payload marking that the drain must
/// replay the atomic quick-log batch (log create + home quick-slot create).
const String quickSlotClaimKey = 'claimQuickSlot';

/// Extra key added to a parked payload carrying the slot winner's details
/// ({occurredOn, byUid, existingLogId}) for the conflict prompt.
const String quickSlotConflictKey = 'slotConflict';

/// `PendingSync.lastError` marker identifying a parked quick-slot conflict.
const String quickSlotConflictError = 'quick_slot_conflict';

/// The day's home quick slot was claimed by another write while this queued
/// quick log waited — a guardian decision, not a retryable failure. The
/// drain parks the item (`needsAttention` + [quickSlotConflictKey]); the UI
/// resolves it via [OfflineService.resolveQuickSlotConflict].
class QuickSlotConflictException implements Exception {
  const QuickSlotConflictException({
    required this.occurredOn,
    this.byUid,
    this.existingLogId,
  });

  final String occurredOn;
  final String? byUid;
  final String? existingLogId;

  @override
  String toString() =>
      'Quick slot for $occurredOn already claimed; guardian must resolve';
}

enum SyncAction {
  create,
  update,
  delete,
}

enum SyncStatus {
  synced,
  syncing,
  pending,
  offline,
}

/// Parent-safe explanation for a stored sync failure.
///
/// The diagnostic queue retains the original backend error for support, but
/// user-facing surfaces must not expose Firebase exception text or imply that
/// a rejected write was lost.
String friendlyOfflineSyncError(String? error) {
  final value = error?.trim().toLowerCase() ?? '';
  if (value.contains('permission-denied') ||
      value.contains('does not have permission')) {
    return "Lumi couldn't upload this because your sign-in or access changed. "
        'Sign in again, or contact your school if you still need access.';
  }
  if (value.contains('unauthenticated') ||
      value.contains('session') && value.contains('expired')) {
    return "Lumi couldn't upload this because your session expired. "
        'Sign in again, then retry.';
  }
  if (value.contains('integrity check failed')) {
    return "Lumi couldn't verify this saved change. It is still on this "
        'device; contact support before dismissing it.';
  }
  if (value.contains('recording file is no longer available')) {
    return "Lumi couldn't find the recording on this device. Record it "
        'again, then dismiss this copy.';
  }
  if (value.contains('invalid-argument') ||
      value.contains('failed-precondition')) {
    return "Lumi couldn't accept this saved change. Check it and try again, "
        'or contact support.';
  }
  return "Lumi couldn't upload this change. It is still saved on this "
      'device; check your connection and try again.';
}

/// Outcome of a single sync attempt, recorded in the diagnostic history.
enum SyncResult {
  success,
  transientFail,
  permanentFail,
  integrityFail,
}

class PendingSync {
  final String id;
  final SyncType type;
  final SyncAction action;
  final Map<String, dynamic> data;
  final DateTime createdAt;

  /// Number of failed attempts so far. Persisted after every attempt.
  int retryCount;

  /// When we last tried to sync this item.
  DateTime? lastAttemptAt;

  /// Earliest time the item is eligible to retry (exponential backoff).
  DateTime? nextAttemptAt;

  /// Human-readable description of the most recent failure.
  String? lastError;

  /// SHA-256 of the canonical payload, stamped at enqueue time. Verified
  /// before each sync to detect Hive corruption.
  String? contentHash;

  /// Set when the failure is permanent (auth/rules/validation) or the payload
  /// failed integrity. Such items are skipped by the drain and surfaced to the
  /// user — never silently dropped, never retried in a tight loop.
  bool needsAttention;

  PendingSync({
    required this.id,
    required this.type,
    required this.action,
    required this.data,
    required this.createdAt,
    this.retryCount = 0,
    this.lastAttemptAt,
    this.nextAttemptAt,
    this.lastError,
    this.contentHash,
    this.needsAttention = false,
  });

  factory PendingSync.fromMap(Map<String, dynamic> map) {
    return PendingSync(
      id: map['id'],
      type: SyncType.values.firstWhere(
        (e) => e.toString() == map['type'],
      ),
      action: SyncAction.values.firstWhere(
        (e) => e.toString() == map['action'],
      ),
      data: Map<String, dynamic>.from(map['data']),
      createdAt: DateTime.parse(map['createdAt']),
      retryCount: map['retryCount'] ?? 0,
      lastAttemptAt: _parseDate(map['lastAttemptAt']),
      nextAttemptAt: _parseDate(map['nextAttemptAt']),
      lastError: map['lastError'] as String?,
      contentHash: map['contentHash'] as String?,
      needsAttention: map['needsAttention'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.toString(),
      'action': action.toString(),
      'data': data,
      'createdAt': createdAt.toIso8601String(),
      'retryCount': retryCount,
      'lastAttemptAt': lastAttemptAt?.toIso8601String(),
      'nextAttemptAt': nextAttemptAt?.toIso8601String(),
      'lastError': lastError,
      'contentHash': contentHash,
      'needsAttention': needsAttention,
    };
  }

  static DateTime? _parseDate(Object? v) =>
      v is String ? DateTime.tryParse(v) : null;

  // Backoff: base * 2^(retryCount-1), capped, plus up to 20% jitter.
  static const int _backoffBaseMs = 5 * 1000; // 5s
  static const int _backoffMaxMs = 30 * 60 * 1000; // 30 min

  static Duration backoffFor(int retryCount, [Random? random]) {
    final n = retryCount < 1 ? 1 : retryCount;
    final shift = (n - 1).clamp(0, 20);
    var ms = _backoffBaseMs * (1 << shift);
    if (ms > _backoffMaxMs) ms = _backoffMaxMs;
    if (random != null) {
      ms = (ms * (1 + random.nextDouble() * 0.2)).round();
      if (ms > _backoffMaxMs) ms = _backoffMaxMs;
    }
    return Duration(milliseconds: ms);
  }

  /// Stable SHA-256 over the payload. Map keys are sorted recursively so the
  /// hash is independent of insertion order.
  static String computeContentHash(Map<String, dynamic> data) {
    final canonical = _canonicalJson(data);
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  static String _canonicalJson(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      final buf = StringBuffer('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) buf.write(',');
        buf
          ..write(jsonEncode(keys[i]))
          ..write(':')
          ..write(_canonicalJson(value[keys[i]]));
      }
      buf.write('}');
      return buf.toString();
    }
    if (value is List) {
      final buf = StringBuffer('[');
      for (var i = 0; i < value.length; i++) {
        if (i > 0) buf.write(',');
        buf.write(_canonicalJson(value[i]));
      }
      buf.write(']');
      return buf.toString();
    }
    return jsonEncode(value);
  }
}

/// One recorded sync attempt, surfaced in the offline-management screen so a
/// real "two weeks never synced" report can be diagnosed.
class SyncHistoryEntry {
  final DateTime at;
  final String itemId;
  final SyncType type;
  final SyncAction action;
  final SyncResult result;
  final String? error;

  SyncHistoryEntry({
    required this.at,
    required this.itemId,
    required this.type,
    required this.action,
    required this.result,
    this.error,
  });

  Map<String, dynamic> toMap() => {
        'at': at.toIso8601String(),
        'itemId': itemId,
        'type': type.toString(),
        'action': action.toString(),
        'result': result.toString(),
        'error': error,
      };

  factory SyncHistoryEntry.fromMap(Map<String, dynamic> map) {
    return SyncHistoryEntry(
      at: DateTime.parse(map['at']),
      itemId: map['itemId'] as String,
      type: SyncType.values.firstWhere((e) => e.toString() == map['type']),
      action:
          SyncAction.values.firstWhere((e) => e.toString() == map['action']),
      result:
          SyncResult.values.firstWhere((e) => e.toString() == map['result']),
      error: map['error'] as String?,
    );
  }
}
