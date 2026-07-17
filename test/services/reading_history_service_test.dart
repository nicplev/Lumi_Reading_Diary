import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/services/reading_history_service.dart';

void main() {
  group('ReadingHistoryService.fetchStudentPage', () {
    late FakeFirebaseFirestore firestore;
    late ReadingHistoryService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = ReadingHistoryService(firestore: firestore);
    });

    Future<void> seed({
      required String schoolId,
      required String id,
      required String studentId,
      required String classId,
      required DateTime date,
    }) async {
      await firestore
          .collection('schools')
          .doc(schoolId)
          .collection('readingLogs')
          .doc(id)
          .set({
        'studentId': studentId,
        'parentId': 'parent-1',
        'schoolId': schoolId,
        'classId': classId,
        'date': Timestamp.fromDate(date),
        'minutesRead': 20,
        'targetMinutes': 20,
        'status': 'completed',
        'bookTitles': ['Book $id'],
        'createdAt': Timestamp.fromDate(date),
      });
    }

    test('keeps reads scoped to the requested school and student', () async {
      await seed(
        schoolId: 'school-a',
        id: 'wanted',
        studentId: 'student-a',
        classId: 'class-a',
        date: DateTime.utc(2026, 7, 17),
      );
      await seed(
        schoolId: 'school-a',
        id: 'other-student',
        studentId: 'student-b',
        classId: 'class-a',
        date: DateTime.utc(2026, 7, 18),
      );
      await seed(
        schoolId: 'school-b',
        id: 'other-school',
        studentId: 'student-a',
        classId: 'class-a',
        date: DateTime.utc(2026, 7, 19),
      );

      final page = await service.fetchStudentPage(
        schoolId: 'school-a',
        studentId: 'student-a',
      );

      expect(page.logs.map((log) => log.id), ['wanted']);
      expect(page.hasMore, isFalse);
    });

    test('teacher scope also requires the requested class', () async {
      await seed(
        schoolId: 'school-a',
        id: 'wanted',
        studentId: 'student-a',
        classId: 'class-a',
        date: DateTime.utc(2026, 7, 17),
      );
      await seed(
        schoolId: 'school-a',
        id: 'wrong-class',
        studentId: 'student-a',
        classId: 'class-b',
        date: DateTime.utc(2026, 7, 18),
      );

      final page = await service.fetchStudentPage(
        schoolId: 'school-a',
        studentId: 'student-a',
        classId: 'class-a',
      );

      expect(page.logs.map((log) => log.id), ['wanted']);
    });

    test('bounds pages and returns the ordered date/document ID cursor',
        () async {
      var day = 14;
      for (final id in ['a', 'b', 'c', 'd']) {
        await seed(
          schoolId: 'school-a',
          id: id,
          studentId: 'student-a',
          classId: 'class-a',
          date: DateTime.utc(2026, 7, day++),
        );
      }

      final first = await service.fetchStudentPage(
        schoolId: 'school-a',
        studentId: 'student-a',
        limit: 2,
      );
      expect(first.logs.map((log) => log.id), ['d', 'c']);
      expect(first.logs, hasLength(2));
      expect(first.hasMore, isTrue);
      expect(first.nextCursor?.documentId, 'c');
      expect(
        first.nextCursor?.date,
        Timestamp.fromDate(DateTime.utc(2026, 7, 16)),
      );
    });

    test('rejects attempts to request an oversized page', () async {
      expect(
        () => service.fetchStudentPage(
          schoolId: 'school-a',
          studentId: 'student-a',
          limit: ReadingHistoryService.maxPageSize + 1,
        ),
        throwsRangeError,
      );
    });
  });
}
