import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_helpers.dart';

/// Tests for Firestore query patterns used by FirebaseService.
///
/// Since FirebaseService is a singleton with late final fields,
/// we test the Firestore query logic directly against FakeFirebaseFirestore.
void main() {
  group('Reading log queries', () {
    late FakeFirebaseFirestore firestore;

    setUp(() async {
      firestore = FakeFirebaseFirestore();

      // Seed test data: 5 reading logs across different dates
      final now = DateTime(2026, 2, 22);
      for (var i = 0; i < 5; i++) {
        final date = now.subtract(Duration(days: i));
        await firestore.collection('readingLogs').doc('log-$i').set({
          ...TestHelpers.sampleReadingLogData(
            logId: 'log-$i',
            studentId: 'student-1',
          ),
          'date': Timestamp.fromDate(date),
        });
      }

      // Add logs for a different student
      await firestore.collection('readingLogs').doc('log-other').set({
        ...TestHelpers.sampleReadingLogData(
          logId: 'log-other',
          studentId: 'student-2',
        ),
        'date': Timestamp.fromDate(now),
      });
    });

    test('fetches all reading logs for a student', () async {
      final snapshot = await firestore
          .collection('readingLogs')
          .where('studentId', isEqualTo: 'student-1')
          .get();

      expect(snapshot.docs.length, 5);
      for (final doc in snapshot.docs) {
        expect(doc.data()['studentId'], 'student-1');
      }
    });

    test('does not return logs for other students', () async {
      final snapshot = await firestore
          .collection('readingLogs')
          .where('studentId', isEqualTo: 'student-1')
          .get();

      final ids = snapshot.docs.map((d) => d.id).toList();
      expect(ids, isNot(contains('log-other')));
    });

    test('filters by start date', () async {
      final startDate = DateTime(2026, 2, 20);
      final snapshot = await firestore
          .collection('readingLogs')
          .where('studentId', isEqualTo: 'student-1')
          .where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .get();

      // Feb 22, 21, 20 = 3 logs
      expect(snapshot.docs.length, 3);
    });

    test('filters by end date', () async {
      final endDate = DateTime(2026, 2, 20);
      final snapshot = await firestore
          .collection('readingLogs')
          .where('studentId', isEqualTo: 'student-1')
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .get();

      // Feb 20, 19, 18 = 3 logs
      expect(snapshot.docs.length, 3);
    });

    test('filters by date range', () async {
      final startDate = DateTime(2026, 2, 19);
      final endDate = DateTime(2026, 2, 21);
      final snapshot = await firestore
          .collection('readingLogs')
          .where('studentId', isEqualTo: 'student-1')
          .where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .get();

      // Feb 19, 20, 21 = 3 logs
      expect(snapshot.docs.length, 3);
    });

    test('returns empty for unknown student', () async {
      final snapshot = await firestore
          .collection('readingLogs')
          .where('studentId', isEqualTo: 'nonexistent')
          .get();

      expect(snapshot.docs, isEmpty);
    });
  });

  group('Student queries', () {
    late FakeFirebaseFirestore firestore;

    setUp(() async {
      firestore = FakeFirebaseFirestore();

      // Active students in class-1
      for (var i = 0; i < 3; i++) {
        await firestore.collection('students').doc('student-$i').set({
          ...TestHelpers.sampleStudentData(
            studentId: 'student-$i',
            classId: 'class-1',
          ),
          'isActive': true,
        });
      }

      // Inactive student in class-1
      await firestore.collection('students').doc('student-inactive').set({
        ...TestHelpers.sampleStudentData(
          studentId: 'student-inactive',
          classId: 'class-1',
        ),
        'isActive': false,
      });

      // Student in a different class
      await firestore.collection('students').doc('student-other').set({
        ...TestHelpers.sampleStudentData(
          studentId: 'student-other',
          classId: 'class-2',
        ),
        'isActive': true,
      });
    });

    test('fetches active students in a class', () async {
      final snapshot = await firestore
          .collection('students')
          .where('classId', isEqualTo: 'class-1')
          .where('isActive', isEqualTo: true)
          .get();

      expect(snapshot.docs.length, 3);
      for (final doc in snapshot.docs) {
        expect(doc.data()['classId'], 'class-1');
        expect(doc.data()['isActive'], true);
      }
    });

    test('excludes inactive students', () async {
      final snapshot = await firestore
          .collection('students')
          .where('classId', isEqualTo: 'class-1')
          .where('isActive', isEqualTo: true)
          .get();

      final ids = snapshot.docs.map((d) => d.id).toList();
      expect(ids, isNot(contains('student-inactive')));
    });

    test('excludes students from other classes', () async {
      final snapshot = await firestore
          .collection('students')
          .where('classId', isEqualTo: 'class-1')
          .where('isActive', isEqualTo: true)
          .get();

      final ids = snapshot.docs.map((d) => d.id).toList();
      expect(ids, isNot(contains('student-other')));
    });

    test('returns empty for class with no students', () async {
      final snapshot = await firestore
          .collection('students')
          .where('classId', isEqualTo: 'empty-class')
          .where('isActive', isEqualTo: true)
          .get();

      expect(snapshot.docs, isEmpty);
    });
  });

  group('User document operations', () {
    late FakeFirebaseFirestore firestore;

    setUp(() async {
      firestore = FakeFirebaseFirestore();

      await firestore.collection('users').doc('user-1').set(
        TestHelpers.sampleUserData(userId: 'user-1', role: 'parent'),
      );
      await firestore.collection('users').doc('user-2').set(
        TestHelpers.sampleUserData(userId: 'user-2', role: 'teacher'),
      );
    });

    test('fetches user by uid', () async {
      final doc = await firestore.collection('users').doc('user-1').get();
      expect(doc.exists, true);
      expect(doc.data()?['role'], 'parent');
    });

    test('returns non-existent for unknown uid', () async {
      final doc =
          await firestore.collection('users').doc('nonexistent').get();
      expect(doc.exists, false);
    });

    test('deletes user document', () async {
      await firestore.collection('users').doc('user-1').delete();
      final doc = await firestore.collection('users').doc('user-1').get();
      expect(doc.exists, false);
    });

    test('updates FCM token', () async {
      await firestore.collection('users').doc('user-1').update({
        'fcmToken': 'new-token',
      });
      final doc = await firestore.collection('users').doc('user-1').get();
      expect(doc.data()?['fcmToken'], 'new-token');
    });
  });
}
