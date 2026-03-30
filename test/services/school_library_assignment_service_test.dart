import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/models/book_model.dart';
import 'package:lumi_reading_tracker/services/school_library_assignment_service.dart';

void main() {
  group('SchoolLibraryAssignmentService', () {
    test('counts current assigned students across active allocations',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = SchoolLibraryAssignmentService(firestore: firestore);
      final now = DateTime.now();

      await firestore
          .collection('schools')
          .doc('school_1')
          .collection('students')
          .doc('student_1')
          .set({
        'name': 'Student One',
        'classId': 'class_a',
        'schoolId': 'school_1',
        'createdAt': Timestamp.fromDate(now),
        'isActive': true,
      });
      await firestore
          .collection('schools')
          .doc('school_1')
          .collection('students')
          .doc('student_2')
          .set({
        'name': 'Student Two',
        'classId': 'class_a',
        'schoolId': 'school_1',
        'createdAt': Timestamp.fromDate(now),
        'isActive': true,
      });
      await firestore
          .collection('schools')
          .doc('school_1')
          .collection('students')
          .doc('student_3')
          .set({
        'name': 'Student Three',
        'classId': 'class_b',
        'schoolId': 'school_1',
        'createdAt': Timestamp.fromDate(now),
        'isActive': true,
      });
      await firestore
          .collection('schools')
          .doc('school_1')
          .collection('students')
          .doc('student_inactive')
          .set({
        'name': 'Inactive Student',
        'classId': 'class_a',
        'schoolId': 'school_1',
        'createdAt': Timestamp.fromDate(now),
        'isActive': false,
      });

      await firestore
          .collection('schools')
          .doc('school_1')
          .collection('allocations')
          .doc('alloc_student')
          .set({
        'schoolId': 'school_1',
        'classId': 'class_a',
        'teacherId': 'teacher_1',
        'studentIds': ['student_1'],
        'type': 'byTitle',
        'cadence': 'weekly',
        'targetMinutes': 20,
        'startDate': Timestamp.fromDate(now.subtract(const Duration(days: 1))),
        'endDate': Timestamp.fromDate(now.add(const Duration(days: 5))),
        'assignmentItems': [
          {
            'id': 'alpha_item_single',
            'title': 'Alpha Book',
            'bookId': 'isbn_111',
            'isbn': '111',
            'isbnNormalized': '111',
            'isDeleted': false,
          },
        ],
        'createdAt': Timestamp.fromDate(now),
        'createdBy': 'teacher_1',
        'isActive': true,
      });

      await firestore
          .collection('schools')
          .doc('school_1')
          .collection('allocations')
          .doc('alloc_class')
          .set({
        'schoolId': 'school_1',
        'classId': 'class_a',
        'teacherId': 'teacher_1',
        'studentIds': <String>[],
        'type': 'byTitle',
        'cadence': 'fortnightly',
        'targetMinutes': 20,
        'startDate': Timestamp.fromDate(now.subtract(const Duration(days: 2))),
        'endDate': Timestamp.fromDate(now.add(const Duration(days: 8))),
        'assignmentItems': [
          {
            'id': 'alpha_item_class',
            'title': 'Alpha Book',
            'bookId': 'isbn_111',
            'isbn': '111',
            'isbnNormalized': '111',
            'isDeleted': false,
          },
          {
            'id': 'beta_item_class',
            'title': 'Beta Book',
            'bookId': 'isbn_222',
            'isbn': '222',
            'isbnNormalized': '222',
            'isDeleted': false,
          },
        ],
        'studentOverrides': {
          'student_2': {
            'removedItemIds': ['alpha_item_class'],
            'addedItems': [
              {
                'id': 'gamma_override',
                'title': 'Gamma Book',
                'bookId': 'isbn_333',
                'isbn': '333',
                'isbnNormalized': '333',
                'isDeleted': false,
              },
            ],
          },
        },
        'createdAt': Timestamp.fromDate(now),
        'createdBy': 'teacher_1',
        'isActive': true,
      });

      await firestore
          .collection('schools')
          .doc('school_1')
          .collection('allocations')
          .doc('alloc_title_only')
          .set({
        'schoolId': 'school_1',
        'classId': 'class_b',
        'teacherId': 'teacher_1',
        'studentIds': ['student_3'],
        'type': 'byTitle',
        'cadence': 'weekly',
        'targetMinutes': 20,
        'startDate': Timestamp.fromDate(now.subtract(const Duration(days: 1))),
        'endDate': Timestamp.fromDate(now.add(const Duration(days: 5))),
        'assignmentItems': [
          {
            'id': 'beta_title_only',
            'title': 'Beta Book',
            'isDeleted': false,
          },
        ],
        'createdAt': Timestamp.fromDate(now),
        'createdBy': 'teacher_1',
        'isActive': true,
      });

      await firestore
          .collection('schools')
          .doc('school_1')
          .collection('allocations')
          .doc('alloc_expired')
          .set({
        'schoolId': 'school_1',
        'classId': 'class_b',
        'teacherId': 'teacher_1',
        'studentIds': ['student_3'],
        'type': 'byTitle',
        'cadence': 'weekly',
        'targetMinutes': 20,
        'startDate': Timestamp.fromDate(now.subtract(const Duration(days: 10))),
        'endDate': Timestamp.fromDate(now.subtract(const Duration(days: 2))),
        'assignmentItems': [
          {
            'id': 'gamma_expired',
            'title': 'Gamma Book',
            'bookId': 'isbn_333',
            'isbn': '333',
            'isbnNormalized': '333',
            'isDeleted': false,
          },
        ],
        'createdAt': Timestamp.fromDate(now),
        'createdBy': 'teacher_1',
        'isActive': true,
      });

      await firestore
          .collection('schools')
          .doc('school_1')
          .collection('allocations')
          .doc('alloc_by_level')
          .set({
        'schoolId': 'school_1',
        'classId': 'class_a',
        'teacherId': 'teacher_1',
        'studentIds': ['student_1'],
        'type': 'byLevel',
        'cadence': 'weekly',
        'targetMinutes': 20,
        'startDate': Timestamp.fromDate(now.subtract(const Duration(days: 1))),
        'endDate': Timestamp.fromDate(now.add(const Duration(days: 5))),
        'createdAt': Timestamp.fromDate(now),
        'createdBy': 'teacher_1',
        'isActive': true,
      });

      final summary = await service.summaryStream('school_1').first;

      final alphaBook = BookModel(
        id: 'isbn_111',
        title: 'Alpha Book',
        isbn: '111',
        createdAt: now,
      );
      final betaBook = BookModel(
        id: 'isbn_222',
        title: 'Beta Book',
        isbn: '222',
        createdAt: now,
      );
      final gammaBook = BookModel(
        id: 'isbn_333',
        title: 'Gamma Book',
        isbn: '333',
        createdAt: now,
      );

      expect(summary.currentAssignedCountForBook(alphaBook), 1);
      expect(summary.currentAssignedCountForBook(betaBook), 3);
      expect(summary.currentAssignedCountForBook(gammaBook), 1);
    });

    test('skips malformed allocation docs without failing the summary',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = SchoolLibraryAssignmentService(firestore: firestore);
      final now = DateTime.now();

      await firestore
          .collection('schools')
          .doc('school_1')
          .collection('students')
          .doc('student_1')
          .set({
        'name': 'Student One',
        'classId': 'class_a',
        'schoolId': 'school_1',
        'createdAt': Timestamp.fromDate(now),
        'isActive': true,
      });

      await firestore
          .collection('schools')
          .doc('school_1')
          .collection('allocations')
          .doc('broken_alloc')
          .set({
        'schoolId': 'school_1',
        'classId': 'class_a',
        'teacherId': 'teacher_1',
        'studentIds': ['student_1'],
        'type': 'byTitle',
        'cadence': 'weekly',
        'targetMinutes': 20,
        'createdAt': Timestamp.fromDate(now),
        'createdBy': 'teacher_1',
        'isActive': true,
      });

      final summary = await service.summaryStream('school_1').first;
      final alphaBook = BookModel(
        id: 'isbn_111',
        title: 'Alpha Book',
        isbn: '111',
        createdAt: now,
      );

      expect(summary.currentAssignedCountForBook(alphaBook), 0);
    });
  });
}
