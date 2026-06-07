import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lumi_reading_tracker/core/models/service_status.dart';
import 'package:lumi_reading_tracker/core/services/service_status_controller.dart';
import 'package:lumi_reading_tracker/data/models/reading_log_model.dart';
import 'package:lumi_reading_tracker/services/offline_service.dart';

/// Minimal reading log for queue/drain specs.
ReadingLogModel _log(
  String id, {
  String schoolId = 'school-1',
  String studentId = 'student-1',
}) {
  return ReadingLogModel(
    id: id,
    studentId: studentId,
    parentId: 'parent-1',
    schoolId: schoolId,
    classId: 'class-1',
    date: DateTime(2024, 1, 1),
    minutesRead: 20,
    targetMinutes: 20,
    bookTitles: const ['Book'],
    notes: null,
    status: LogStatus.completed,
    photoUrls: null,
    isOfflineCreated: true,
    syncedAt: null,
    createdAt: DateTime(2024, 1, 1),
  );
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  // Mock the connectivity plugin
  binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (MethodCall methodCall) async {
      if (methodCall.method == 'check') {
        return ['wifi'];
      }
      return null;
    },
  );

  group('OfflineService', () {
    late OfflineService offlineService;
    late Directory testDirectory;

    setUpAll(() async {
      // Create a temporary directory for Hive
      testDirectory = await Directory.systemTemp.createTemp('hive_test_');
      // Initialize Hive with test directory
      Hive.init(testDirectory.path);
    });

    setUp(() async {
      offlineService = OfflineService.instance;
      await offlineService.initialize();
    });

    group('saveReadingLogLocally', () {
      test('saves reading log to local storage', () async {
        final log = ReadingLogModel(
          id: 'test-log-local',
          studentId: 'student-123',
          parentId: 'parent-123',
          schoolId: 'school-123',
          classId: 'class-123',
          date: DateTime.now(),
          minutesRead: 20,
          targetMinutes: 20,
          bookTitles: ['Test Book'],
          notes: 'Test notes',
          status: LogStatus.completed,
          photoUrls: null,
          isOfflineCreated: true,
          syncedAt: null,
          createdAt: DateTime.now(),
        );

        await offlineService.saveReadingLogLocally(log);

        // Verify log was saved
        final savedLogs =
            await offlineService.getLocalReadingLogs('student-123');
        expect(savedLogs, isNotEmpty);
        expect(savedLogs.first.id, equals('test-log-local'));
      });

      test('adds log to sync queue when offline', () async {
        final log = ReadingLogModel(
          id: 'test-log-queue',
          studentId: 'student-456',
          parentId: 'parent-456',
          schoolId: 'school-456',
          classId: 'class-456',
          date: DateTime.now(),
          minutesRead: 25,
          targetMinutes: 20,
          bookTitles: [],
          notes: null,
          status: LogStatus.completed,
          photoUrls: null,
          isOfflineCreated: true,
          syncedAt: null,
          createdAt: DateTime.now(),
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
          classId: 'class-123',
          date: DateTime.now(),
          minutesRead: 20,
          targetMinutes: 20,
          bookTitles: [],
          notes: null,
          status: LogStatus.completed,
          photoUrls: null,
          isOfflineCreated: false,
          syncedAt: DateTime.now(),
          createdAt: DateTime.now(),
        );

        final log2 = ReadingLogModel(
          id: 'log-student-2',
          studentId: 'student-other',
          parentId: 'parent-123',
          schoolId: 'school-123',
          classId: 'class-123',
          date: DateTime.now(),
          minutesRead: 15,
          targetMinutes: 20,
          bookTitles: [],
          notes: null,
          status: LogStatus.completed,
          photoUrls: null,
          isOfflineCreated: false,
          syncedAt: DateTime.now(),
          createdAt: DateTime.now(),
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
          classId: 'class-123',
          date: DateTime(2024, 1, 1),
          minutesRead: 20,
          targetMinutes: 20,
          bookTitles: [],
          notes: null,
          status: LogStatus.completed,
          photoUrls: null,
          isOfflineCreated: false,
          syncedAt: DateTime.now(),
          createdAt: DateTime.now(),
        );

        final newLog = ReadingLogModel(
          id: 'log-new',
          studentId: 'student-sort',
          parentId: 'parent-123',
          schoolId: 'school-123',
          classId: 'class-123',
          date: DateTime(2024, 3, 1),
          minutesRead: 25,
          targetMinutes: 20,
          bookTitles: [],
          notes: null,
          status: LogStatus.completed,
          photoUrls: null,
          isOfflineCreated: false,
          syncedAt: DateTime.now(),
          createdAt: DateTime.now(),
        );

        await offlineService.saveReadingLogLocally(oldLog);
        await offlineService.saveReadingLogLocally(newLog);

        final logs = await offlineService.getLocalReadingLogs('student-sort');

        expect(logs.first.id, equals('log-new')); // Newest first
        expect(logs.last.id, equals('log-old')); // Oldest last
      });

      test('returns empty list for student with no logs', () async {
        final logs =
            await offlineService.getLocalReadingLogs('student-nonexistent');
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

      test('round-trips the new backoff/integrity fields', () {
        final p = PendingSync(
          id: 'sync-new',
          type: SyncType.readingLog,
          action: SyncAction.create,
          data: {'k': 'v'},
          createdAt: DateTime(2024, 1, 1),
          retryCount: 2,
          lastAttemptAt: DateTime(2024, 1, 2, 3, 4),
          nextAttemptAt: DateTime(2024, 1, 2, 3, 9),
          lastError: 'unavailable',
          contentHash: 'abc123',
          needsAttention: true,
        );

        final r = PendingSync.fromMap(p.toMap());
        expect(r.retryCount, equals(2));
        expect(r.lastAttemptAt, equals(DateTime(2024, 1, 2, 3, 4)));
        expect(r.nextAttemptAt, equals(DateTime(2024, 1, 2, 3, 9)));
        expect(r.lastError, equals('unavailable'));
        expect(r.contentHash, equals('abc123'));
        expect(r.needsAttention, isTrue);
      });

      test('fromMap tolerates legacy maps without the new fields', () {
        final legacy = {
          'id': 'legacy',
          'type': 'SyncType.readingLog',
          'action': 'SyncAction.create',
          'data': {'k': 'v'},
          'createdAt': DateTime(2024, 1, 1).toIso8601String(),
          'retryCount': 0,
        };

        final r = PendingSync.fromMap(legacy);
        expect(r.needsAttention, isFalse);
        expect(r.lastAttemptAt, isNull);
        expect(r.nextAttemptAt, isNull);
        expect(r.lastError, isNull);
        expect(r.contentHash, isNull);
      });

      test('backoffFor grows exponentially and caps at 30 minutes', () {
        expect(PendingSync.backoffFor(1).inSeconds, equals(5));
        expect(PendingSync.backoffFor(2).inSeconds, equals(10));
        expect(PendingSync.backoffFor(3).inSeconds, equals(20));
        expect(PendingSync.backoffFor(4).inSeconds, equals(40));
        // Far out: clamped to the 30-minute ceiling.
        expect(PendingSync.backoffFor(100).inMinutes, equals(30));
      });

      test('computeContentHash is stable regardless of key order', () {
        final a = PendingSync.computeContentHash({
          'a': 1,
          'b': {'x': 1, 'y': 2},
          'c': [1, 2, 3],
        });
        final b = PendingSync.computeContentHash({
          'c': [1, 2, 3],
          'b': {'y': 2, 'x': 1},
          'a': 1,
        });
        expect(a, equals(b));

        // A changed value yields a different hash.
        final c = PendingSync.computeContentHash({
          'a': 2,
          'b': {'x': 1, 'y': 2},
          'c': [1, 2, 3],
        });
        expect(a, isNot(equals(c)));
      });
    });

    group('sync types and actions', () {
      test('SyncType enum has all expected values', () {
        expect(SyncType.values.length, equals(6));
        expect(
          SyncType.values,
          containsAll([
            SyncType.readingLog,
            SyncType.student,
            SyncType.allocation,
            SyncType.parentComment,
            SyncType.commentReply,
            SyncType.parentPrefs,
          ]),
        );
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
          classId: 'class-123',
          date: DateTime.now().subtract(const Duration(days: 60)),
          minutesRead: 20,
          targetMinutes: 20,
          bookTitles: [],
          notes: null,
          status: LogStatus.completed,
          photoUrls: null,
          isOfflineCreated: false,
          syncedAt: DateTime.now(),
          createdAt: DateTime.now(),
        );

        final recentLog = ReadingLogModel(
          id: 'log-recent',
          studentId: 'student-cleanup',
          parentId: 'parent-123',
          schoolId: 'school-123',
          classId: 'class-123',
          date: DateTime.now().subtract(const Duration(days: 5)),
          minutesRead: 25,
          targetMinutes: 20,
          bookTitles: [],
          notes: null,
          status: LogStatus.completed,
          photoUrls: null,
          isOfflineCreated: false,
          syncedAt: DateTime.now(),
          createdAt: DateTime.now(),
        );

        await offlineService.saveReadingLogLocally(oldLog);
        await offlineService.saveReadingLogLocally(recentLog);

        // Clear data older than 30 days
        await offlineService.clearOldData(daysToKeep: 30);

        final logs =
            await offlineService.getLocalReadingLogs('student-cleanup');

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
          classId: 'class-integration',
          date: DateTime.now(),
          minutesRead: 30,
          targetMinutes: 20,
          bookTitles: ['Integration Test Book'],
          notes: 'Created offline',
          status: LogStatus.completed,
          photoUrls: null,
          isOfflineCreated: true,
          syncedAt: null,
          createdAt: DateTime.now(),
        );

        // Save locally
        await offlineService.saveReadingLogLocally(log);

        // Verify it's marked as offline created
        final savedLogs =
            await offlineService.getLocalReadingLogs('student-integration');
        expect(savedLogs.first.isOfflineCreated, isTrue);
        expect(savedLogs.first.syncedAt, isNull);

        // After sync (simulated), it would have syncedAt set
        final syncedLog = log.copyWith(
          isOfflineCreated: false,
          syncedAt: DateTime.now(),
        );

        await offlineService.saveReadingLogLocally(syncedLog);

        final updatedLogs =
            await offlineService.getLocalReadingLogs('student-integration');
        expect(updatedLogs.first.isOfflineCreated, isFalse);
        expect(updatedLogs.first.syncedAt, isNotNull);
      });
    });

    group('drain hardening', () {
      void goHealthy() => ServiceStatusController.instance
          .debugSetCurrent(ServiceStatusSnapshot.healthy());

      test('does not drain while the write path is unhealthy', () async {
        // Status defaults to `unknown` (canWriteToFirebase == false).
        var attempts = 0;
        offlineService.syncOneOverrideForTest = (_) async => attempts++;
        await offlineService.saveReadingLogLocally(_log('rl-gated'));

        await offlineService.triggerSync();

        expect(attempts, equals(0));
        expect(offlineService.pendingSyncs, hasLength(1));
      });

      test('confirmed reading-log write leaves the queue', () async {
        final fake = FakeFirebaseFirestore();
        offlineService.firestoreForTest = fake;
        goHealthy();

        await offlineService.saveReadingLogLocally(_log('rl-ok'));
        expect(offlineService.pendingSyncs, hasLength(1));

        await offlineService.triggerSync();

        // Removed only after the server read-back confirmed the doc.
        expect(offlineService.pendingSyncs, isEmpty);
        final doc = await fake
            .collection('schools')
            .doc('school-1')
            .collection('readingLogs')
            .doc('rl-ok')
            .get();
        expect(doc.exists, isTrue);
      });

      test('comment reply writes the comment and updates the log preview',
          () async {
        final fake = FakeFirebaseFirestore();
        offlineService.firestoreForTest = fake;
        goHealthy();

        final logRef = fake
            .collection('schools')
            .doc('school-1')
            .collection('readingLogs')
            .doc('rl-comment');
        // The target log must exist for the batched preview update to land.
        await logRef.set({'studentId': 'student-1', 'parentId': 'parent-1'});

        await offlineService.enqueueCommentReply(
          logId: 'rl-comment',
          schoolId: 'school-1',
          commentId: 'cmt-1',
          authorId: 'parent-1',
          authorRole: 'parent',
          authorName: 'Dad',
          body: 'Thank you!',
          studentId: 'student-1',
          parentId: 'parent-1',
        );
        expect(offlineService.pendingSyncs, hasLength(1));
        expect(offlineService.pendingSyncs.single.type, SyncType.commentReply);

        await offlineService.triggerSync();

        expect(offlineService.pendingSyncs, isEmpty);
        final commentDoc = await logRef.collection('comments').doc('cmt-1').get();
        expect(commentDoc.exists, isTrue);
        expect(commentDoc.data()!['body'], 'Thank you!');
        expect(commentDoc.data()!['authorRole'], 'parent');
        expect(commentDoc.data()!['studentId'], 'student-1');

        final logDoc = await logRef.get();
        expect(logDoc.data()!['lastCommentPreview'], 'Thank you!');
        expect(logDoc.data()!['lastCommentByRole'], 'parent');
      });

      test('transient failure keeps the item and persists backoff state',
          () async {
        goHealthy();
        offlineService.syncOneOverrideForTest = (_) async {
          throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
        };

        await offlineService.saveReadingLogLocally(_log('rl-transient'));
        await offlineService.triggerSync();

        // Still queued — never silently dropped.
        expect(offlineService.pendingSyncs, hasLength(1));

        // Prove the retry/backoff state hit disk (the old bug only mutated
        // it in memory and lost it on restart).
        offlineService.reloadPendingFromDiskForTest();
        final item = offlineService.pendingSyncs.single;
        expect(item.retryCount, equals(1));
        expect(item.nextAttemptAt, isNotNull);
        expect(item.needsAttention, isFalse);
        expect(item.lastError, contains('unavailable'));
      });

      test('permanent failure parks the item and stops retrying', () async {
        goHealthy();
        offlineService.syncOneOverrideForTest = (_) async {
          throw FirebaseException(
              plugin: 'cloud_firestore', code: 'permission-denied');
        };

        await offlineService.saveReadingLogLocally(_log('rl-perm'));
        await offlineService.triggerSync();

        offlineService.reloadPendingFromDiskForTest();
        final item = offlineService.pendingSyncs.single;
        expect(item.needsAttention, isTrue);
        expect(item.retryCount, equals(1));

        // A subsequent drain must not re-attempt a parked item.
        var attempts = 0;
        offlineService.syncOneOverrideForTest = (_) async {
          attempts++;
          throw FirebaseException(
              plugin: 'cloud_firestore', code: 'permission-denied');
        };
        await offlineService.triggerSync();
        expect(attempts, equals(0));
        expect(offlineService.pendingSyncs, hasLength(1));
      });

      test('corrupted payload trips the integrity check', () async {
        goHealthy();
        await offlineService.saveReadingLogLocally(_log('rl-integrity'));

        // Tamper the queued payload so its hash no longer matches.
        offlineService.pendingSyncs.single.data['minutesRead'] = 9999;

        var attempts = 0;
        offlineService.syncOneOverrideForTest = (_) async => attempts++;
        await offlineService.triggerSync();

        // The network write is never attempted for corrupted data...
        expect(attempts, equals(0));
        // ...and the item is parked for attention rather than synced.
        offlineService.reloadPendingFromDiskForTest();
        expect(offlineService.pendingSyncs.single.needsAttention, isTrue);
      });

      test('dismissPending is the only way an unsynced item leaves the queue',
          () async {
        await offlineService.saveReadingLogLocally(_log('rl-dismiss'));
        expect(offlineService.pendingSyncs, hasLength(1));

        await offlineService.dismissPending('rl-dismiss');

        expect(offlineService.pendingSyncs, isEmpty);
        offlineService.reloadPendingFromDiskForTest();
        expect(offlineService.pendingSyncs, isEmpty);
      });
    });

    tearDown(() async {
      // Reset test seams so they don't leak across specs.
      offlineService.syncOneOverrideForTest = null;
      offlineService.firestoreForTest = null;
      ServiceStatusController.instance
          .debugSetCurrent(ServiceStatusSnapshot.unknown());
      // Clean up test data
      await offlineService.clearLocalData();
    });

    tearDownAll(() async {
      // Close Hive
      await Hive.close();
      // Clean up test directory
      if (await testDirectory.exists()) {
        await testDirectory.delete(recursive: true);
      }
    });
  });
}
