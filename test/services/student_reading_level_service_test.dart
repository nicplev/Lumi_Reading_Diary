import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/models/student_model.dart';
import 'package:lumi_reading_tracker/data/models/user_model.dart';
import 'package:lumi_reading_tracker/services/reading_level_service.dart';
import 'package:lumi_reading_tracker/services/student_reading_level_service.dart';

void main() {
  group('StudentReadingLevelService', () {
    late FakeFirebaseFirestore firestore;
    late ReadingLevelService readingLevelService;
    late StudentReadingLevelService service;
    late UserModel teacher;
    late StudentModel student;
    final now = DateTime(2026, 3, 15, 8, 0, 0);

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      readingLevelService = ReadingLevelService(firestore: firestore);
      service = StudentReadingLevelService(
        firestore: firestore,
        readingLevelService: readingLevelService,
      );
      teacher = UserModel(
        id: 'teacher_1',
        email: 'teacher@test.com',
        fullName: 'Teacher One',
        role: UserRole.teacher,
        schoolId: 'school_1',
        createdAt: now,
      );

      await firestore.collection('schools').doc('school_1').set({
        'name': 'Test School',
        'createdBy': 'admin_1',
        'createdAt': Timestamp.fromDate(now),
        'levelSchema': 'aToZ',
      });

      await firestore
          .collection('schools')
          .doc('school_1')
          .collection('students')
          .doc('student_1')
          .set({
        'firstName': 'Emma',
        'lastName': 'Wilson',
        'schoolId': 'school_1',
        'classId': 'class_1',
        'currentReadingLevel': 'A',
        'parentIds': <String>[],
        'isActive': true,
        'createdAt': Timestamp.fromDate(now),
      });

      student = StudentModel(
        id: 'student_1',
        firstName: 'Emma',
        lastName: 'Wilson',
        schoolId: 'school_1',
        classId: 'class_1',
        currentReadingLevel: 'A',
        createdAt: now,
      );
    });

    test('updates current level metadata and creates an event', () async {
      final options = await readingLevelService.loadSchoolLevels('school_1');

      final didUpdate = await service.updateStudentLevel(
        actor: teacher,
        student: student,
        options: options,
        newLevel: 'B',
        reason: 'Running record result',
      );

      expect(didUpdate, isTrue);

      final updatedStudent = await firestore
          .collection('schools')
          .doc('school_1')
          .collection('students')
          .doc('student_1')
          .get();
      final updatedData = updatedStudent.data()!;

      expect(updatedData['currentReadingLevel'], 'B');
      expect(updatedData['currentReadingLevelIndex'], 1);
      expect(updatedData['readingLevelUpdatedBy'], 'teacher_1');
      expect(updatedData['readingLevelSource'], 'teacher');
      expect(updatedData['levelHistory'], isNotEmpty);

      final eventsSnapshot = await firestore
          .collection('schools')
          .doc('school_1')
          .collection('students')
          .doc('student_1')
          .collection('readingLevelEvents')
          .get();

      expect(eventsSnapshot.docs, hasLength(1));
      final eventData = eventsSnapshot.docs.first.data();
      expect(eventData['fromLevel'], 'A');
      expect(eventData['toLevel'], 'B');
      expect(eventData['reason'], 'Running record result');
      expect(eventData['changedByUserId'], 'teacher_1');
    });

    test('returns false when the canonical level does not change', () async {
      final options = await readingLevelService.loadSchoolLevels('school_1');

      final didUpdate = await service.updateStudentLevel(
        actor: teacher,
        student: student,
        options: options,
        newLevel: 'Level A',
      );

      expect(didUpdate, isFalse);

      final eventsSnapshot = await firestore
          .collection('schools')
          .doc('school_1')
          .collection('students')
          .doc('student_1')
          .collection('readingLevelEvents')
          .get();

      expect(eventsSnapshot.docs, isEmpty);
    });

    test('bulk updates multiple students and skips no-op records', () async {
      await firestore
          .collection('schools')
          .doc('school_1')
          .collection('students')
          .doc('student_2')
          .set({
        'firstName': 'Liam',
        'lastName': 'Chen',
        'schoolId': 'school_1',
        'classId': 'class_1',
        'currentReadingLevel': 'B',
        'parentIds': <String>[],
        'isActive': true,
        'createdAt': Timestamp.fromDate(now),
      });

      final options = await readingLevelService.loadSchoolLevels('school_1');
      final secondStudent = StudentModel(
        id: 'student_2',
        firstName: 'Liam',
        lastName: 'Chen',
        schoolId: 'school_1',
        classId: 'class_1',
        currentReadingLevel: 'B',
        createdAt: now,
      );

      final updatedCount = await service.bulkUpdateStudentLevels(
        actor: teacher,
        students: [student, secondStudent],
        options: options,
        newLevel: 'C',
        reason: 'Small group regrouping',
        source: StudentReadingLevelService.sourceBulkTeacher,
      );

      expect(updatedCount, 2);

      final studentOne = await firestore
          .collection('schools')
          .doc('school_1')
          .collection('students')
          .doc('student_1')
          .get();
      final studentTwo = await firestore
          .collection('schools')
          .doc('school_1')
          .collection('students')
          .doc('student_2')
          .get();

      expect(studentOne.data()!['currentReadingLevel'], 'C');
      expect(studentTwo.data()!['currentReadingLevel'], 'C');

      final studentOneEvents = await firestore
          .collection('schools')
          .doc('school_1')
          .collection('students')
          .doc('student_1')
          .collection('readingLevelEvents')
          .get();
      final studentTwoEvents = await firestore
          .collection('schools')
          .doc('school_1')
          .collection('students')
          .doc('student_2')
          .collection('readingLevelEvents')
          .get();

      expect(studentOneEvents.docs, hasLength(1));
      expect(studentTwoEvents.docs, hasLength(1));
      expect(
        studentOneEvents.docs.first.data()['source'],
        StudentReadingLevelService.sourceBulkTeacher,
      );
    });
  });
}
