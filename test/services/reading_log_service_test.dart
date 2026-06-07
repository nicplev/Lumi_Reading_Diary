import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/models/service_status.dart';
import 'package:lumi_reading_tracker/core/services/service_status_controller.dart';
import 'package:lumi_reading_tracker/data/models/student_model.dart';
import 'package:lumi_reading_tracker/data/models/user_model.dart';
import 'package:lumi_reading_tracker/services/reading_log_service.dart';

/// Stats-preview behaviour of [ReadingLogService.writeLog].
///
/// Since the redesign, the client is NOT the source of truth for stats — the
/// aggregateStudentStats Cloud Function is. [writeLog] writes the log doc and
/// returns a display-only *preview* (for the success-screen celebration) but
/// must never mutate `students/{id}.stats`. These tests inject a
/// [FakeFirebaseFirestore] via [ReadingLogService.forTest] to verify both the
/// preview values (incl. the forgiving rest-day tolerance) and the
/// no-persist guarantee.
void main() {
  group('ReadingLogService.writeLog (preview-only)', () {
    late FakeFirebaseFirestore firestore;
    late ReadingLogService service;
    const schoolId = 'school_1';
    const studentId = 'student_1';
    const parentId = 'parent_1';

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = ReadingLogService.forTest(firestore: firestore);
      // Force the online write path so writeLog persists the log + previews
      // stats (rather than queuing offline).
      ServiceStatusController.instance
          .debugSetCurrent(ServiceStatusSnapshot.healthy());
    });

    tearDown(() {
      ServiceStatusController.instance
          .debugSetCurrent(ServiceStatusSnapshot.unknown());
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

    /// Seeds the Firestore student doc with the supplied stats map.
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

    /// Reads the raw persisted student document.
    Future<Map<String, dynamic>> readRawStudent() async {
      final doc = await firestore
          .collection('schools')
          .doc(schoolId)
          .collection('students')
          .doc(studentId)
          .get();
      return doc.data()!;
    }

    test('writes the log doc and returns a streak=1 preview, persisting no stats',
        () async {
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

      // The preview reflects the first night.
      expect(result.updatedStats?['currentStreak'], 1);
      expect(result.updatedStats?['totalReadingDays'], 1);
      expect(result.updatedStats?['totalMinutesRead'], 15);
      expect(result.restDayApplied, isFalse);
      expect(result.savedOffline, isFalse);

      // The client did NOT write stats — that's the Cloud Function's job.
      expect(readRawStudent().then((d) => d.containsKey('stats')),
          completion(isFalse));
    });

    test('same-day repeat: preview keeps the streak and does not double-count',
        () async {
      await seedStudent({
        'currentStreak': 1,
        'totalReadingDays': 1,
        'totalMinutesRead': 10,
        'lastReadingDate': Timestamp.fromDate(DateTime.now()),
      });

      final result = await service.logReading(
        student: buildStudent(),
        parent: buildParent(),
        minutesRead: 12,
      );

      expect(result.updatedStats?['currentStreak'], 1,
          reason: 'same day → streak unchanged');
      expect(result.updatedStats?['totalReadingDays'], 1,
          reason: 'same day → night not counted again');
      expect(result.updatedStats?['totalMinutesRead'], 22,
          reason: 'minutes still accrue in the preview');
      expect(result.restDayApplied, isFalse);
    });

    test('one missed night: preview bridges the streak and flags a rest day',
        () async {
      // Last log 2 calendar days ago → yesterday was missed (within tolerance).
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      await seedStudent({
        'currentStreak': 5,
        'totalReadingDays': 5,
        'lastReadingDate': Timestamp.fromDate(twoDaysAgo),
      });

      final result = await service.logReading(
        student: buildStudent(),
        parent: buildParent(),
        minutesRead: 15,
      );

      expect(result.restDayApplied, isTrue);
      expect(result.updatedStats?['currentStreak'], 6,
          reason: 'rest-day tolerance bridges the missed night');
    });

    test('three missed nights: preview restarts the streak with no rest day',
        () async {
      final fourDaysAgo = DateTime.now().subtract(const Duration(days: 4));
      await seedStudent({
        'currentStreak': 5,
        'totalReadingDays': 5,
        'lastReadingDate': Timestamp.fromDate(fourDaysAgo),
      });

      final result = await service.logReading(
        student: buildStudent(),
        parent: buildParent(),
        minutesRead: 15,
      );

      expect(result.restDayApplied, isFalse);
      expect(result.updatedStats?['currentStreak'], 1,
          reason: 'beyond the 2-day tolerance → fresh start');
    });

    test('never persists computed stats (Cloud Function is the source of truth)',
        () async {
      final seeded = {
        'currentStreak': 5,
        'longestStreak': 9,
        'totalReadingDays': 5,
        'totalMinutesRead': 100,
        'lastReadingDate':
            Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 2))),
      };
      await seedStudent(seeded);

      await service.logReading(
        student: buildStudent(),
        parent: buildParent(),
        minutesRead: 15,
      );

      final stats = (await readRawStudent())['stats'] as Map<String, dynamic>;
      expect(stats['currentStreak'], 5, reason: 'untouched by the client');
      expect(stats['totalReadingDays'], 5, reason: 'untouched by the client');
      expect(stats['totalMinutesRead'], 100, reason: 'untouched by the client');
    });
  });
}
