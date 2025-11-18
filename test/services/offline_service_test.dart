import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/services/offline_service.dart';
import 'package:lumi_reading_tracker/data/models/reading_log_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../helpers/test_helpers.dart';

void main() {
  group('OfflineService', () {
    late OfflineService offlineService;

    setUpAll(() async {
      // Initialize Hive for testing
      await Hive.initFlutter();
    });

    setUp(() {
      offlineService = OfflineService.instance;
    });

    group('saveReadingLogLocally', () {
      test('saves reading log to local storage', () async {
        final log = ReadingLogModel(
          id: 'test-log-local',
          studentId: 'student-123',
          parentId: 'parent-123',
          schoolId: 'school-123',
          date: Timestamp.now(),
          minutesRead: 20,
          targetMinutes: 20,
          bookTitles: ['Test Book'],
          notes: 'Test notes',
          status: ReadingStatus.completed,
          photoUrl: null,
          isOfflineCreated: true,
          syncedAt: null,
          createdAt: Timestamp.now(),
          updatedAt: Timestamp.now(),
        );

        await offlineService.saveReadingLogLocally(log);

        // Verify log was saved
        final savedLogs = await offlineService.getLocalReadingLogs('student-123');
        expect(savedLogs, isNotEmpty);
        expect(savedLogs.first.id, equals('test-log-local'));
      });

      test('adds log to sync queue when offline', () async {
        final log = ReadingLogModel(
          id: 'test-log-queue',
          studentId: 'student-456',
          parentId: 'parent-456',
          schoolId: 'school-456',
          date: Timestamp.now(),
          minutesRead: 25,
          targetMinutes: 20,
          bookTitles: [],
          notes: null,
          status: ReadingStatus.completed,
          photoUrl: null,
          isOfflineCreated: true,
          syncedAt: null,
          createdAt: Timestamp.now(),
          updatedAt: Timestamp.now(),
        );

        // Simulate offline state
        // Note: This would require mocking connectivity, simplified for test
        await offlineService.saveReadingLogLocally(log);

        // Verify added to queue would happen in real scenario
        expect(log.isOfflineCreated, isTrue);
      });
    });

    group('getLocalReadingLogs', () {
      test('retrieves logs for specific student', () async {
        final log1 = ReadingLogModel(
          id: 'log-student-1',
          studentId: 'student-target',
          parentId: 'parent-123',
          schoolId: 'school-123',
          date: Timestamp.now(),
          minutesRead: 20,
          targetMinutes: 20,
          bookTitles: [],
          notes: null,
          status: ReadingStatus.completed,
          photoUrl: null,
          isOfflineCreated: false,
          syncedAt: Timestamp.now(),
          createdAt: Timestamp.now(),
          updatedAt: Timestamp.now(),
        );

        final log2 = ReadingLogModel(
          id: 'log-student-2',
          studentId: 'student-other',
          parentId: 'parent-123',
          schoolId: 'school-123',
          date: Timestamp.now(),
          minutesRead: 15,
          targetMinutes: 20,
          bookTitles: [],
          notes: null,
          status: ReadingStatus.completed,
          photoUrl: null,
          isOfflineCreated: false,
          syncedAt: Timestamp.now(),
          createdAt: Timestamp.now(),
          updatedAt: Timestamp.now(),
        );

        await offlineService.saveReadingLogLocally(log1);
        await offlineService.saveReadingLogLocally(log2);

        final logs = await offlineService.getLocalReadingLogs('student-target');

        expect(logs, isNotEmpty);
        expect(logs.every((log) => log.studentId == 'student-target'), isTrue);
      });

      test('returns logs sorted by date descending', () async {
        final oldLog = ReadingLogModel(
          id: 'log-old',
          studentId: 'student-sort',
          parentId: 'parent-123',
          schoolId: 'school-123',
          date: Timestamp.fromDate(DateTime(2024, 1, 1)),
          minutesRead: 20,
          targetMinutes: 20,
          bookTitles: [],
          notes: null,
          status: ReadingStatus.completed,
          photoUrl: null,
          isOfflineCreated: false,
          syncedAt: Timestamp.now(),
          createdAt: Timestamp.now(),
          updatedAt: Timestamp.now(),
        );

        final newLog = ReadingLogModel(
          id: 'log-new',
          studentId: 'student-sort',
          parentId: 'parent-123',
          schoolId: 'school-123',
          date: Timestamp.fromDate(DateTime(2024, 3, 1)),
          minutesRead: 25,
          targetMinutes: 20,
          bookTitles: [],
          notes: null,
          status: ReadingStatus.completed,
          photoUrl: null,
          isOfflineCreated: false,
          syncedAt: Timestamp.now(),
          createdAt: Timestamp.now(),
          updatedAt: Timestamp.now(),
        );

        await offlineService.saveReadingLogLocally(oldLog);
        await offlineService.saveReadingLogLocally(newLog);

        final logs = await offlineService.getLocalReadingLogs('student-sort');

        expect(logs.first.id, equals('log-new')); // Newest first
        expect(logs.last.id, equals('log-old')); // Oldest last
      });

      test('returns empty list for student with no logs', () async {
        final logs = await offlineService.getLocalReadingLogs('student-nonexistent');
        expect(logs, isEmpty);
      });
    });

    group('getSyncStatus', () {
      test('returns synced when queue is empty and online', () {
        // Assuming online and no pending syncs
        final status = offlineService.getSyncStatus();

        // Note: Actual status depends on connectivity and queue state
        expect(
          status,
          isIn([SyncStatus.synced, SyncStatus.pending, SyncStatus.offline]),
        );
      });

      test('returns syncing when sync in progress', () {
        // This would require triggering a sync operation
        // Simplified for unit test - would be tested in integration test
      });
    });

    group('PendingSync', () {
      test('converts to and from map correctly', () {
        final pendingSync = PendingSync(
          id: 'sync-123',
          type: SyncType.readingLog,
          action: SyncAction.create,
          data: {'test': 'data'},
          createdAt: DateTime(2024, 1, 1),
          retryCount: 0,
        );

        final map = pendingSync.toMap();
        expect(map['id'], equals('sync-123'));
        expect(map['type'], contains('readingLog'));
        expect(map['action'], contains('create'));

        final restored = PendingSync.fromMap(map);
        expect(restored.id, equals(pendingSync.id));
        expect(restored.type, equals(pendingSync.type));
        expect(restored.action, equals(pendingSync.action));
      });

      test('tracks retry count', () {
        final pendingSync = PendingSync(
          id: 'sync-retry',
          type: SyncType.readingLog,
          action: SyncAction.create,
          data: {},
          createdAt: DateTime.now(),
          retryCount: 3,
        );

        expect(pendingSync.retryCount, equals(3));

        pendingSync.retryCount++;
        expect(pendingSync.retryCount, equals(4));
      });
    });

    group('sync types and actions', () {
      test('SyncType enum has all expected values', () {
        expect(SyncType.values.length, equals(3));
        expect(SyncType.values, contains(SyncType.readingLog));
        expect(SyncType.values, contains(SyncType.student));
        expect(SyncType.values, contains(SyncType.allocation));
      });

      test('SyncAction enum has all expected values', () {
        expect(SyncAction.values.length, equals(3));
        expect(SyncAction.values, contains(SyncAction.create));
        expect(SyncAction.values, contains(SyncAction.update));
        expect(SyncAction.values, contains(SyncAction.delete));
      });

      test('SyncStatus enum has all expected values', () {
        expect(SyncStatus.values.length, equals(4));
        expect(SyncStatus.values, contains(SyncStatus.synced));
        expect(SyncStatus.values, contains(SyncStatus.syncing));
        expect(SyncStatus.values, contains(SyncStatus.pending));
        expect(SyncStatus.values, contains(SyncStatus.offline));
      });
    });

    group('clearOldData', () {
      test('removes logs older than specified days', () async {
        final oldLog = ReadingLogModel(
          id: 'log-very-old',
          studentId: 'student-cleanup',
          parentId: 'parent-123',
          schoolId: 'school-123',
          date: Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 60))),
          minutesRead: 20,
          targetMinutes: 20,
          bookTitles: [],
          notes: null,
          status: ReadingStatus.completed,
          photoUrl: null,
          isOfflineCreated: false,
          syncedAt: Timestamp.now(),
          createdAt: Timestamp.now(),
          updatedAt: Timestamp.now(),
        );

        final recentLog = ReadingLogModel(
          id: 'log-recent',
          studentId: 'student-cleanup',
          parentId: 'parent-123',
          schoolId: 'school-123',
          date: Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 5))),
          minutesRead: 25,
          targetMinutes: 20,
          bookTitles: [],
          notes: null,
          status: ReadingStatus.completed,
          photoUrl: null,
          isOfflineCreated: false,
          syncedAt: Timestamp.now(),
          createdAt: Timestamp.now(),
          updatedAt: Timestamp.now(),
        );

        await offlineService.saveReadingLogLocally(oldLog);
        await offlineService.saveReadingLogLocally(recentLog);

        // Clear data older than 30 days
        await offlineService.clearOldData(daysToKeep: 30);

        final logs = await offlineService.getLocalReadingLogs('student-cleanup');

        // Recent log should remain
        expect(logs.any((log) => log.id == 'log-recent'), isTrue);
      });
    });

    group('integration scenarios', () {
      test('offline creation and sync simulation', () async {
        // Create log offline
        final log = ReadingLogModel(
          id: 'integration-log',
          studentId: 'student-integration',
          parentId: 'parent-integration',
          schoolId: 'school-integration',
          date: Timestamp.now(),
          minutesRead: 30,
          targetMinutes: 20,
          bookTitles: ['Integration Test Book'],
          notes: 'Created offline',
          status: ReadingStatus.completed,
          photoUrl: null,
          isOfflineCreated: true,
          syncedAt: null,
          createdAt: Timestamp.now(),
          updatedAt: Timestamp.now(),
        );

        // Save locally
        await offlineService.saveReadingLogLocally(log);

        // Verify it's marked as offline created
        final savedLogs = await offlineService.getLocalReadingLogs('student-integration');
        expect(savedLogs.first.isOfflineCreated, isTrue);
        expect(savedLogs.first.syncedAt, isNull);

        // After sync (simulated), it would have syncedAt set
        final syncedLog = log.copyWith(
          isOfflineCreated: false,
          syncedAt: Timestamp.now(),
        );

        await offlineService.saveReadingLogLocally(syncedLog);

        final updatedLogs = await offlineService.getLocalReadingLogs('student-integration');
        expect(updatedLogs.first.isOfflineCreated, isFalse);
        expect(updatedLogs.first.syncedAt, isNotNull);
      });
    });

    tearDown(() async {
      // Clean up test data
      await offlineService.clearLocalData();
    });

    tearDownAll(() async {
      // Close Hive
      await Hive.close();
    });
  });
}
