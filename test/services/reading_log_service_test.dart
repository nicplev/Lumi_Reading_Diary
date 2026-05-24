import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/models/student_model.dart';
import 'package:lumi_reading_tracker/data/models/user_model.dart';
import 'package:lumi_reading_tracker/services/reading_log_service.dart';

/// Stat-update + streak-freeze behaviour of [ReadingLogService.writeLog].
///
/// These tests exercise the Firestore transaction by injecting a
/// [FakeFirebaseFirestore] via [ReadingLogService.forTest]. They verify the
/// streak/freeze accounting that drives the parent-home indicator + the
/// "Freeze used — streak protected!" success copy (Rec 6).
void main() {
  group('ReadingLogService.writeLog stats + freezes', () {
    late FakeFirebaseFirestore firestore;
    late ReadingLogService service;
    const schoolId = 'school_1';
    const studentId = 'student_1';
    const parentId = 'parent_1';

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = ReadingLogService.forTest(firestore: firestore);
    });

    UserModel buildParent() => UserModel(
          id: parentId,
          email: 'p@example.com',
          fullName: 'Parent One',
          role: UserRole.parent,
          schoolId: schoolId,
          createdAt: DateTime(2026, 1, 1),
        );

    StudentModel buildStudent({StudentStats? stats}) => StudentModel(
          id: studentId,
          firstName: 'Sam',
          lastName: 'Reader',
          schoolId: schoolId,
          classId: 'class_1',
          createdAt: DateTime(2026, 1, 1),
          stats: stats,
        );

    /// Seeds the Firestore student doc with the supplied stats map. The doc
    /// must exist before the writeLog transaction runs.
    Future<void> seedStudent(Map<String, dynamic>? stats) async {
      await firestore
          .collection('schools')
          .doc(schoolId)
          .collection('students')
          .doc(studentId)
          .set({
        'firstName': 'Sam',
        'lastName': 'Reader',
        'schoolId': schoolId,
        'classId': 'class_1',
        if (stats != null) 'stats': stats,
      });
    }

    Future<Map<String, dynamic>> readStats() async {
      final doc = await firestore
          .collection('schools')
          .doc(schoolId)
          .collection('students')
          .doc(studentId)
          .get();
      return (doc.data()!['stats'] as Map<String, dynamic>);
    }

    test('first log persists the log doc and seeds streak=1', () async {
      await seedStudent(null);

      final result = await service.logReading(
        student: buildStudent(),
        parent: buildParent(),
        minutesRead: 15,
      );

      // The log doc was written to schools/{schoolId}/readingLogs.
      final logs = await firestore
          .collection('schools')
          .doc(schoolId)
          .collection('readingLogs')
          .get();
      expect(logs.docs, hasLength(1));
      expect(logs.docs.first.data()['studentId'], studentId);

      // Stats freshly seeded.
      final stats = await readStats();
      expect(stats['currentStreak'], 1);
      expect(stats['longestStreak'], 1);
      expect(stats['totalReadingDays'], 1);
      expect(stats['totalMinutesRead'], 15);
      expect(stats['streakFreezesAvailable'],
          StudentStats.defaultStreakFreezes);
      expect(stats['streakFreezesUsed'], 0);

      expect(result.freezeUsed, isFalse);
      expect(result.savedOffline, isFalse);
    });

    test('same-day repeat does not double-count totalReadingDays', () async {
      await seedStudent({
        'currentStreak': 1,
        'totalReadingDays': 1,
        'totalMinutesRead': 10,
        'lastReadingDate': Timestamp.fromDate(DateTime.now()),
        'streakFreezesAvailable': StudentStats.defaultStreakFreezes,
        'streakFreezesUsed': 0,
      });

      await service.logReading(
        student: buildStudent(),
        parent: buildParent(),
        minutesRead: 12,
      );

      final stats = await readStats();
      expect(stats['currentStreak'], 1, reason: 'same day → streak unchanged');
      expect(stats['totalReadingDays'], 1, reason: 'same day → not counted');
      expect(stats['totalMinutesRead'], 22, reason: 'minutes still accrue');
    });

    test('1-day gap with freeze available spends a freeze and keeps streak',
        () async {
      // Last log was 2 calendar days ago — i.e. yesterday was skipped.
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      await seedStudent({
        'currentStreak': 5,
        'totalReadingDays': 5,
        'lastReadingDate': Timestamp.fromDate(twoDaysAgo),
        'streakFreezesAvailable': 2,
        'streakFreezesUsed': 0,
      });

      final result = await service.logReading(
        student: buildStudent(),
        parent: buildParent(),
        minutesRead: 15,
      );

      final stats = await readStats();
      expect(result.freezeUsed, isTrue);
      expect(stats['currentStreak'], 6, reason: 'freeze protected the streak');
      expect(stats['streakFreezesAvailable'], 1, reason: 'one freeze spent');
      expect(stats['streakFreezesUsed'], 1);
    });

    test('1-day gap without freezes resets the streak to 1', () async {
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      await seedStudent({
        'currentStreak': 5,
        'totalReadingDays': 5,
        'lastReadingDate': Timestamp.fromDate(twoDaysAgo),
        'streakFreezesAvailable': 0,
        'streakFreezesUsed': 2,
      });

      final result = await service.logReading(
        student: buildStudent(),
        parent: buildParent(),
        minutesRead: 15,
      );

      final stats = await readStats();
      expect(result.freezeUsed, isFalse);
      expect(stats['currentStreak'], 1, reason: 'no freezes → streak resets');
      expect(stats['streakFreezesAvailable'], 0);
    });

    test('streak crossing a multiple of 7 earns back a freeze (capped)',
        () async {
      // Logged yesterday on a streak of 6 → today extends to 7 → earn back.
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await seedStudent({
        'currentStreak': 6,
        'totalReadingDays': 6,
        'lastReadingDate': Timestamp.fromDate(yesterday),
        // Below the cap so a freeze can be earned.
        'streakFreezesAvailable': 1,
        'streakFreezesUsed': 1,
      });

      await service.logReading(
        student: buildStudent(),
        parent: buildParent(),
        minutesRead: 20,
      );

      final stats = await readStats();
      expect(stats['currentStreak'], 7);
      expect(stats['streakFreezesAvailable'], 2,
          reason: 'earn-back fires at multiples of 7');
      expect(stats['streakFreezeLastEarnedDate'], isNotNull);
    });

    test('earn-back is capped at the default', () async {
      // Already at the cap → multiple-of-7 streak should NOT exceed it.
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await seedStudent({
        'currentStreak': 6,
        'totalReadingDays': 6,
        'lastReadingDate': Timestamp.fromDate(yesterday),
        'streakFreezesAvailable': StudentStats.defaultStreakFreezes,
        'streakFreezesUsed': 0,
      });

      await service.logReading(
        student: buildStudent(),
        parent: buildParent(),
        minutesRead: 20,
      );

      final stats = await readStats();
      expect(stats['currentStreak'], 7);
      expect(stats['streakFreezesAvailable'],
          StudentStats.defaultStreakFreezes,
          reason: 'cap respected — no extra freeze added');
    });
  });
}
