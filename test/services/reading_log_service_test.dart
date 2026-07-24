import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/models/service_status.dart';
import 'package:lumi_reading_tracker/core/services/service_status_controller.dart';
import 'package:lumi_reading_tracker/data/models/reading_log_model.dart';
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
  test('generateLogId returns unique 128-bit random hex identifiers', () {
    final ids = List.generate(100, (_) => ReadingLogService.generateLogId());
    expect(ids.toSet(), hasLength(ids.length));
    for (final id in ids) {
      expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
    }
  });

  test('comprehension audio uploads use the private pending prefix', () {
    expect(
      ReadingLogService.comprehensionAudioUploadStoragePath(
        schoolId: 'school_1',
        logId: 'log_1',
      ),
      'comprehension_audio_uploads/school_1/log_1.m4a',
    );
  });

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

    // writeLog fail-closes on access (StudentAccessInactiveException), so
    // fixtures carry a live entitlement like every real student doc.
    StudentModel buildStudent({StudentStats? stats, StudentAccess? access}) =>
        StudentModel(
          id: studentId,
          firstName: 'Sam',
          lastName: 'Reader',
          schoolId: schoolId,
          classId: 'class_1',
          createdAt: DateTime(2026, 1, 1),
          stats: stats,
          access: access ??
              StudentAccess(
                status: StudentAccess.statusActive,
                academicYear: 2026,
                expiresAt: DateTime.now().add(const Duration(days: 365)),
              ),
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

    test(
        'writes the log doc and returns a streak=1 preview, persisting no stats',
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
      expect(logs.docs.first.data()['loggedByRole'], 'parent');
      expect(result.log.loggedByRole, LoggedByRole.parent);

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

    test(
        'never persists computed stats (Cloud Function is the source of truth)',
        () async {
      final seeded = {
        'currentStreak': 5,
        'longestStreak': 9,
        'totalReadingDays': 5,
        'totalMinutesRead': 100,
        'lastReadingDate': Timestamp.fromDate(
            DateTime.now().subtract(const Duration(days: 2))),
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

    test('quick log throws when the school disables quick logging', () async {
      await firestore.collection('schools').doc(schoolId).set({
        'name': 'Lumi School',
        'settings': {
          'quickLogging': {'enabled': false},
        },
      });
      await seedStudent(null);

      await expectLater(
        service.logReading(
          student: buildStudent(),
          parent: buildParent(),
          // Explicit title so book resolution succeeds and the school-level
          // gate (not NoCurrentBookException) is what fires.
          bookTitles: const ['The Bad Guys'],
          quickLog: true,
        ),
        throwsA(isA<QuickLoggingDisabledException>()),
      );

      final logs = await firestore
          .collection('schools')
          .doc(schoolId)
          .collection('readingLogs')
          .get();
      expect(logs.docs, isEmpty);
    });

    test('identifier-only quick log writes explicit parent attribution',
        () async {
      await seedStudent(null);

      final result = await service.logQuickFromIds(
        studentId: studentId,
        parentId: parentId,
        schoolId: schoolId,
        classId: 'class_1',
        bookTitle: 'The Bad Guys',
      );

      final raw = (await firestore
              .collection('schools')
              .doc(schoolId)
              .collection('readingLogs')
              .doc(result.log.id)
              .get())
          .data()!;
      expect(result.log.loggedByRole, LoggedByRole.parent);
      expect(raw['loggedByRole'], 'parent');
    });

    test('identifier-only quick log with no title throws — never fabricates',
        () async {
      await seedStudent(null);

      // buildLog throws synchronously (before a Future exists), so assert on
      // the closure rather than the call expression.
      expect(
        () => service.logQuickFromIds(
          studentId: studentId,
          parentId: parentId,
          schoolId: schoolId,
          classId: 'class_1',
        ),
        throwsA(isA<NoCurrentBookException>()),
      );

      final logs = await firestore
          .collection('schools')
          .doc(schoolId)
          .collection('readingLogs')
          .get();
      expect(logs.docs, isEmpty);
    });

    test(
        'quick log with no resolvable book throws NoCurrentBookException '
        'and writes nothing', () async {
      await seedStudent(null);

      expect(
        () => service.logReading(
          student: buildStudent(),
          parent: buildParent(),
          quickLog: true, // no allocations, no explicit titles
        ),
        throwsA(isA<NoCurrentBookException>()),
      );

      final logs = await firestore
          .collection('schools')
          .doc(schoolId)
          .collection('readingLogs')
          .get();
      expect(logs.docs, isEmpty, reason: "no fabricated 'Reading' title ever");
    });

    test('inactive access throws before any write or queue', () async {
      await seedStudent(null);

      await expectLater(
        service.logReading(
          student: buildStudent(
            access: StudentAccess(
              status: StudentAccess.statusActive,
              academicYear: 2025,
              expiresAt: DateTime.now().subtract(const Duration(days: 1)),
            ),
          ),
          parent: buildParent(),
          bookTitles: const ['Zog'],
        ),
        throwsA(isA<StudentAccessInactiveException>()),
      );
    });
  });

  group('ReadingLogService quick-slot claim', () {
    late FakeFirebaseFirestore firestore;
    late ReadingLogService service;
    const schoolId = 'school_1';
    const studentId = 'student_1';

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = ReadingLogService.forTest(firestore: firestore);
      ServiceStatusController.instance
          .debugSetCurrent(ServiceStatusSnapshot.healthy());
    });

    tearDown(() {
      ServiceStatusController.instance
          .debugSetCurrent(ServiceStatusSnapshot.unknown());
    });

    UserModel parentUser(String uid) => UserModel(
          id: uid,
          email: '$uid@example.com',
          fullName: 'Parent $uid',
          role: UserRole.parent,
          schoolId: schoolId,
          createdAt: DateTime(2026, 1, 1),
        );

    StudentModel student() => StudentModel(
          id: studentId,
          firstName: 'Lincoln',
          lastName: 'Reader',
          schoolId: schoolId,
          classId: 'class_1',
          createdAt: DateTime(2026, 1, 1),
          access: StudentAccess(
            status: StudentAccess.statusActive,
            academicYear: 2026,
            expiresAt: DateTime.now().add(const Duration(days: 365)),
          ),
        );

    DocumentReference<Map<String, dynamic>> slotRef(String date) => firestore
        .collection('schools')
        .doc(schoolId)
        .collection('students')
        .doc(studentId)
        .collection('quickSlots')
        .doc(date);

    test('quick log stamps occurredOn/context and claims the day slot',
        () async {
      final result = await service.logReading(
        student: student(),
        parent: parentUser('parent_a'),
        bookTitles: const ['The Bad Guys'],
        quickLog: true,
      );

      expect(result.log.occurredOn, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(result.log.context, 'home');

      final raw = (await firestore
              .collection('schools')
              .doc(schoolId)
              .collection('readingLogs')
              .doc(result.log.id)
              .get())
          .data()!;
      expect(raw['occurredOn'], result.log.occurredOn);
      expect(raw['context'], 'home');

      final slot = await slotRef(result.log.occurredOn!).get();
      expect(slot.exists, isTrue);
      expect(slot.data()!['logId'], result.log.id);
      expect(slot.data()!['byUid'], 'parent_a');
    });

    test('second quick log for the day throws QuickSlotTakenException '
        'with the winner and writes nothing', () async {
      final first = await service.logReading(
        student: student(),
        parent: parentUser('parent_a'),
        bookTitles: const ['The Bad Guys'],
        minutesRead: 20,
        quickLog: true,
      );

      await expectLater(
        service.logReading(
          student: student(),
          parent: parentUser('parent_b'),
          bookTitles: const ['The Bad Guys'],
          quickLog: true,
        ),
        throwsA(isA<QuickSlotTakenException>()
            .having((e) => e.byUid, 'byUid', 'parent_a')
            .having((e) => e.existingLogId, 'existingLogId', first.log.id)
            .having((e) => e.existingLog?.minutesRead, 'winner minutes', 20)),
      );

      final logs = await firestore
          .collection('schools')
          .doc(schoolId)
          .collection('readingLogs')
          .get();
      expect(logs.docs, hasLength(1), reason: 'the loser wrote nothing');
    });

    test('claimQuickSlot: false adds a separate session without touching '
        'the slot', () async {
      await service.logReading(
        student: student(),
        parent: parentUser('parent_a'),
        bookTitles: const ['The Bad Guys'],
        quickLog: true,
      );
      final extra = await service.logReading(
        student: student(),
        parent: parentUser('parent_b'),
        bookTitles: const ['Zog'],
        quickLog: true,
        claimQuickSlot: false,
      );

      final logs = await firestore
          .collection('schools')
          .doc(schoolId)
          .collection('readingLogs')
          .get();
      expect(logs.docs, hasLength(2));

      final slot = await slotRef(extra.log.occurredOn!).get();
      expect(slot.data()!['byUid'], 'parent_a',
          reason: 'the additional session never rebinds the slot');
    });

    test('deleteOwnLog removes exactly that session and frees its slot',
        () async {
      final result = await service.logReading(
        student: student(),
        parent: parentUser('parent_a'),
        bookTitles: const ['The Bad Guys'],
        quickLog: true,
      );

      await service.deleteOwnLog(result.log);

      final log = await firestore
          .collection('schools')
          .doc(schoolId)
          .collection('readingLogs')
          .doc(result.log.id)
          .get();
      expect(log.exists, isFalse);
      expect((await slotRef(result.log.occurredOn!).get()).exists, isFalse,
          reason: 'undo frees the day slot for the co-guardian');
    });

    test("deleteOwnLog leaves a sibling session's slot alone", () async {
      final first = await service.logReading(
        student: student(),
        parent: parentUser('parent_a'),
        bookTitles: const ['The Bad Guys'],
        quickLog: true,
      );
      final extra = await service.logReading(
        student: student(),
        parent: parentUser('parent_a'),
        bookTitles: const ['Zog'],
        quickLog: true,
        claimQuickSlot: false,
      );

      await service.deleteOwnLog(extra.log);

      final slot = await slotRef(first.log.occurredOn!).get();
      expect(slot.exists, isTrue);
      expect(slot.data()!['logId'], first.log.id);
    });
  });
}
