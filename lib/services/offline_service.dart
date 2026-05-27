import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import '../core/models/service_status.dart';
import '../core/services/service_status_controller.dart';
import '../data/models/reading_log_model.dart';
import '../data/models/student_model.dart';
import '../data/models/allocation_model.dart';
import 'firebase_service.dart';
import 'reading_log_service.dart';

class OfflineService {
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

  // Sync queue
  final List<PendingSync> _syncQueue = [];
  Timer? _syncTimer;
  bool _isSyncing = false;

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
  DateTime? get lastSuccessfulSyncAt {
    if (!_initialized) return null;
    final raw = _serviceMetaBox.get('lastSuccessfulSyncAt');
    return raw is String ? DateTime.tryParse(raw) : null;
  }

  Future<void> initialize() async {
    try {
      // Open Hive boxes
      _readingLogsBox = await Hive.openBox<Map>('reading_logs');
      _studentsBox = await Hive.openBox<Map>('students');
      _allocationsBox = await Hive.openBox<Map>('allocations');
      _pendingSyncBox = await Hive.openBox<Map>('pending_sync');
      _settingsBox = await Hive.openBox<Map>('settings');
      _logDraftsBox = await Hive.openBox<Map>('log_drafts');
      _serviceMetaBox = await Hive.openBox<dynamic>('service_meta');

      // Load pending syncs
      _loadPendingSyncs();

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

      // Start sync timer
      _startSyncTimer();

      _initialized = true;
      debugPrint('Offline service initialized');
    } catch (e) {
      debugPrint('Error initializing offline service: $e');
      rethrow;
    }
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
      _syncQueue.clear();
      debugPrint('All offline caches cleared');
    } catch (e) {
      debugPrint('Error clearing offline caches: $e');
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
      if (_isOnline && _syncQueue.isNotEmpty) {
        _syncPendingData();
      }
    });
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
  /// button on the service-status sheet. Coalesces with an in-flight sync.
  Future<void> triggerSync() => _syncPendingData();

  Future<void> _enqueueAndPersist(PendingSync sync) async {
    await _pendingSyncBox.put(sync.id, sync.toMap());
    _syncQueue.add(sync);
    _broadcastQueue();
  }

  /// Save reading log locally AND queue it for sync. Callers only invoke
  /// this from the offline-fallback path, so queuing is unconditional —
  /// `_isOnline` (a pure connectivity check) is too narrow now that
  /// `ServiceStatusController.canWriteToFirebase` also covers
  /// `firebaseDown` and `degraded`.
  Future<void> saveReadingLogLocally(ReadingLogModel log) async {
    try {
      await _readingLogsBox.put(log.id, log.toLocal());
      await _enqueueAndPersist(PendingSync(
        id: log.id,
        type: SyncType.readingLog,
        action: SyncAction.create,
        data: log.toLocal(),
        createdAt: DateTime.now(),
      ));
    } catch (e) {
      debugPrint('Error saving reading log locally: $e');
      rethrow;
    }
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

  /// Queue a parent-preferences update. Dedupes — multiple offline edits
  /// to the same parent collapse to the latest values.
  Future<void> enqueueParentPrefs({
    required String parentId,
    required String schoolId,
    required Map<String, dynamic> preferences,
  }) async {
    final syncId = 'prefs_$parentId';
    final existing =
        _syncQueue.indexWhere((p) => p.id == syncId && p.type == SyncType.parentPrefs);
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
      final data = _studentsBox.get(studentId);
      if (data != null) {
        // Create a fake DocumentSnapshot for StudentModel
        final docData = Map<String, dynamic>.from(data);
        // StudentModel expects a DocumentSnapshot, so we'll need to handle this differently
        // For now, return null and rely on online data
        return null;
      }
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

  // Sync pending data
  Future<void> _syncPendingData() async {
    if (_isSyncing || !_isOnline || _syncQueue.isEmpty) {
      return;
    }

    _isSyncing = true;
    debugPrint('Starting sync of ${_syncQueue.length} pending items...');

    final firebaseService = FirebaseService.instance;
    final syncedItems = <String>[];

    // Drain in priority order: reading-log creates first (so dependent
    // comment writes have a doc to target), then comments, then prefs,
    // then any other types in their natural order.
    final ordered = List<PendingSync>.from(_syncQueue)
      ..sort((a, b) => _syncPriority(a.type).compareTo(_syncPriority(b.type)));

    for (final pendingSync in ordered) {
      try {
        switch (pendingSync.type) {
          case SyncType.readingLog:
            await _syncReadingLog(pendingSync, firebaseService);
            break;
          case SyncType.student:
            await _syncStudent(pendingSync, firebaseService);
            break;
          case SyncType.allocation:
            await _syncAllocation(pendingSync, firebaseService);
            break;
          case SyncType.parentComment:
            await _syncParentComment(pendingSync, firebaseService);
            break;
          case SyncType.parentPrefs:
            await _syncParentPrefs(pendingSync, firebaseService);
            break;
        }

        syncedItems.add(pendingSync.id);
        debugPrint('Synced: ${pendingSync.type} - ${pendingSync.id}');
      } catch (e) {
        debugPrint('Error syncing ${pendingSync.type}: $e');

        // Increment retry count
        pendingSync.retryCount++;

        // Remove from queue if max retries exceeded
        if (pendingSync.retryCount >= 5) {
          syncedItems.add(pendingSync.id);
          debugPrint(
              'Max retries exceeded for ${pendingSync.id}, removing from queue');
        }
      }
    }

    // Remove synced items from queue and storage
    for (final id in syncedItems) {
      _syncQueue.removeWhere((item) => item.id == id);
      await _pendingSyncBox.delete(id);
    }

    _isSyncing = false;
    if (syncedItems.isNotEmpty) {
      final now = DateTime.now();
      await _serviceMetaBox.put(
          'lastSuccessfulSyncAt', now.toIso8601String());
      if (!_lastSyncController.isClosed) _lastSyncController.add(now);
    }
    _broadcastQueue();
    debugPrint('Sync completed. Remaining items: ${_syncQueue.length}');
  }

  /// Lower number → drained earlier. Reading-log creates must precede any
  /// parent-comment updates that target the same log.
  int _syncPriority(SyncType type) {
    switch (type) {
      case SyncType.readingLog:
        return 0;
      case SyncType.parentComment:
        return 1;
      case SyncType.student:
        return 2;
      case SyncType.allocation:
        return 3;
      case SyncType.parentPrefs:
        return 4;
    }
  }

  Future<void> _syncReadingLog(
    PendingSync pendingSync,
    FirebaseService firebaseService,
  ) async {
    final log = ReadingLogModel.fromLocal(pendingSync.data);

    // Get the school ID from the log data
    final schoolId = pendingSync.data['schoolId'] as String?;
    if (schoolId == null) {
      throw Exception('Missing schoolId for reading log sync');
    }

    final logRef = firebaseService.firestore
        .collection('schools')
        .doc(schoolId)
        .collection('readingLogs')
        .doc(log.id);

    switch (pendingSync.action) {
      case SyncAction.create:
        // Check for conflicts before creating
        final existingDoc = await logRef.get();
        if (existingDoc.exists) {
          // Conflict: document already exists
          debugPrint('Conflict detected for reading log ${log.id}');
          await _resolveReadingLogConflict(log, existingDoc, logRef);
        } else {
          await logRef.set(log.toFirestore());
        }
        break;
      case SyncAction.update:
        // For updates, use server timestamp to detect conflicts
        final existingDoc = await logRef.get();
        if (existingDoc.exists) {
          await _resolveReadingLogConflict(log, existingDoc, logRef);
        } else {
          // Document was deleted remotely, treat as create
          await logRef.set(log.toFirestore());
        }
        break;
      case SyncAction.delete:
        await logRef.delete();
        break;
    }

    // Update local copy with synced timestamp
    final syncedLog = log.copyWith(
      syncedAt: DateTime.now(),
      isOfflineCreated: false,
    );
    await _readingLogsBox.put(log.id, syncedLog.toLocal());

    // Replay the stats transaction for offline-created logs. Without this,
    // queued logs reached Firestore but streaks and freeze counters never
    // advanced (latent pre-redesign bug).
    if (pendingSync.action == SyncAction.create) {
      await ReadingLogService.instance.recomputeStatsAfterSync(syncedLog);
    }
  }

  Future<void> _syncParentComment(
    PendingSync pendingSync,
    FirebaseService firebaseService,
  ) async {
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

    final logRef = firebaseService.firestore
        .collection('schools')
        .doc(schoolId)
        .collection('readingLogs')
        .doc(logId);

    await logRef.update({
      'parentCommentSelections': selections,
      'parentCommentFreeText':
          (freeText != null && freeText.isNotEmpty) ? freeText : null,
      'parentComment':
          (composed != null && composed.isNotEmpty) ? composed : null,
    });
  }

  Future<void> _syncParentPrefs(
    PendingSync pendingSync,
    FirebaseService firebaseService,
  ) async {
    final parentId = pendingSync.data['parentId'] as String?;
    final schoolId = pendingSync.data['schoolId'] as String?;
    final prefs = pendingSync.data['preferences'];
    if (parentId == null || schoolId == null || prefs is! Map) {
      throw Exception('Missing parentId/schoolId/preferences for prefs sync');
    }

    final parentRef = firebaseService.firestore
        .collection('schools')
        .doc(schoolId)
        .collection('parents')
        .doc(parentId);

    await parentRef.update({
      'preferences': Map<String, dynamic>.from(prefs),
    });
  }

  /// Resolve conflicts when syncing reading logs
  Future<void> _resolveReadingLogConflict(
    ReadingLogModel localLog,
    dynamic remoteDoc,
    dynamic logRef,
  ) async {
    final remoteData = remoteDoc.data() as Map<String, dynamic>?;
    if (remoteData == null) {
      // Remote was deleted, use local
      await logRef.set(localLog.toFirestore());
      return;
    }

    // Simple conflict resolution: Last write wins based on timestamp
    final localTimestamp = localLog.syncedAt?.millisecondsSinceEpoch ?? 0;
    final remoteTimestamp =
        (remoteData['syncedAt'] as dynamic)?.millisecondsSinceEpoch ?? 0;

    if (localTimestamp > remoteTimestamp) {
      // Local is newer, use local
      debugPrint('Local version is newer, updating remote');
      await logRef.update(localLog.toFirestore());
    } else {
      // Remote is newer, keep remote and update local
      debugPrint('Remote version is newer, updating local');
      final remoteLog = ReadingLogModel.fromFirestore(remoteDoc);
      await _readingLogsBox.put(localLog.id, remoteLog.toLocal());
    }
  }

  Future<void> _syncStudent(
    PendingSync pendingSync,
    FirebaseService firebaseService,
  ) async {
    final studentData = Map<String, dynamic>.from(pendingSync.data);
    final studentId = pendingSync.id;
    final schoolId = studentData['schoolId'] as String?;

    if (schoolId == null) {
      throw Exception('Missing schoolId for student sync');
    }

    final studentRef = firebaseService.firestore
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

  Future<void> _syncAllocation(
    PendingSync pendingSync,
    FirebaseService firebaseService,
  ) async {
    final allocationData = Map<String, dynamic>.from(pendingSync.data);
    final allocationId = pendingSync.id;
    final schoolId = allocationData['schoolId'] as String?;

    if (schoolId == null) {
      throw Exception('Missing schoolId for allocation sync');
    }

    final allocationRef = firebaseService.firestore
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

  // Clear all local data
  Future<void> clearLocalData() async {
    if (!_initialized) return;
    await _readingLogsBox.clear();
    await _studentsBox.clear();
    await _allocationsBox.clear();
    await _pendingSyncBox.clear();
    await _logDraftsBox.clear();
    _syncQueue.clear();
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
    if (!_queueController.isClosed) _queueController.close();
    if (!_lastSyncController.isClosed) _lastSyncController.close();
  }
}

// Sync models
enum SyncType {
  readingLog,
  student,
  allocation,
  parentComment,
  parentPrefs,
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

class PendingSync {
  final String id;
  final SyncType type;
  final SyncAction action;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  int retryCount;

  PendingSync({
    required this.id,
    required this.type,
    required this.action,
    required this.data,
    required this.createdAt,
    this.retryCount = 0,
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
    };
  }
}
