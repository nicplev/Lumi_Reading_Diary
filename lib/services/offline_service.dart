import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import '../data/models/reading_log_model.dart';
import '../data/models/student_model.dart';
import '../data/models/allocation_model.dart';
import 'firebase_service.dart';

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

  // Connectivity
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isOnline = true;

  // Sync queue
  final List<PendingSync> _syncQueue = [];
  Timer? _syncTimer;
  bool _isSyncing = false;

  // Getters
  bool get isOnline => _isOnline;
  List<PendingSync> get pendingSyncs => _syncQueue;

  Future<void> initialize() async {
    try {
      // Open Hive boxes
      _readingLogsBox = await Hive.openBox<Map>('reading_logs');
      _studentsBox = await Hive.openBox<Map>('students');
      _allocationsBox = await Hive.openBox<Map>('allocations');
      _pendingSyncBox = await Hive.openBox<Map>('pending_sync');
      _settingsBox = await Hive.openBox<Map>('settings');

      // Load pending syncs
      _loadPendingSyncs();

      // Check initial connectivity
      await _checkConnectivity();

      // Listen to connectivity changes
      _connectivitySubscription =
          _connectivity.onConnectivityChanged.listen(_handleConnectivityChange);

      // Start sync timer
      _startSyncTimer();

      debugPrint('Offline service initialized');
    } catch (e) {
      debugPrint('Error initializing offline service: $e');
      rethrow;
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
  }

  // Save reading log locally
  Future<void> saveReadingLogLocally(ReadingLogModel log) async {
    try {
      await _readingLogsBox.put(log.id, log.toLocal());

      // Add to sync queue if offline
      if (!_isOnline) {
        final pendingSync = PendingSync(
          id: log.id,
          type: SyncType.readingLog,
          action: SyncAction.create,
          data: log.toLocal(),
          createdAt: DateTime.now(),
        );

        await _pendingSyncBox.put(pendingSync.id, pendingSync.toMap());
        _syncQueue.add(pendingSync);
      }
    } catch (e) {
      debugPrint('Error saving reading log locally: $e');
      rethrow;
    }
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

    for (final pendingSync in List.from(_syncQueue)) {
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
    debugPrint('Sync completed. Remaining items: ${_syncQueue.length}');
  }

  Future<void> _syncReadingLog(
    PendingSync pendingSync,
    FirebaseService firebaseService,
  ) async {
    final log = ReadingLogModel.fromLocal(pendingSync.data);

    switch (pendingSync.action) {
      case SyncAction.create:
        await firebaseService.firestore
            .collection('readingLogs')
            .doc(log.id)
            .set(log.toFirestore());
        break;
      case SyncAction.update:
        await firebaseService.firestore
            .collection('readingLogs')
            .doc(log.id)
            .update(log.toFirestore());
        break;
      case SyncAction.delete:
        await firebaseService.firestore
            .collection('readingLogs')
            .doc(log.id)
            .delete();
        break;
    }

    // Update local copy with synced timestamp
    final syncedLog = log.copyWith(
      syncedAt: DateTime.now(),
      isOfflineCreated: false,
    );
    await _readingLogsBox.put(log.id, syncedLog.toLocal());
  }

  Future<void> _syncStudent(
    PendingSync pendingSync,
    FirebaseService firebaseService,
  ) async {
    // Implement student sync
    // Similar to reading log sync
  }

  Future<void> _syncAllocation(
    PendingSync pendingSync,
    FirebaseService firebaseService,
  ) async {
    // Implement allocation sync
    // Similar to reading log sync
  }

  // Clear all local data
  Future<void> clearLocalData() async {
    await _readingLogsBox.clear();
    await _studentsBox.clear();
    await _allocationsBox.clear();
    await _pendingSyncBox.clear();
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
    _syncTimer?.cancel();
  }
}

// Sync models
enum SyncType {
  readingLog,
  student,
  allocation,
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
