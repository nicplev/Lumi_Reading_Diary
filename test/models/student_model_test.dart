import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/models/student_model.dart';
import '../helpers/test_helpers.dart';

void main() {
  group('StudentModel', () {
    late Map<String, dynamic> testData;

    setUp(() {
      testData = TestHelpers.sampleStudentData();
    });

    group('fromFirestore', () {
      test('creates student model from Firestore document', () async {
        final firestore = TestHelpers.createFakeFirestore();
        await firestore.collection('students').doc('test-student-123').set(testData);

        final doc = await firestore.collection('students').doc('test-student-123').get();
        final student = StudentModel.fromFirestore(doc);

        expect(student.id, equals('test-student-123'));
        expect(student.firstName, equals('Emma'));
        expect(student.lastName, equals('Watson'));
        expect(student.studentId, equals('STU001'));
        expect(student.schoolId, equals('test-school-123'));
        expect(student.classId, equals('test-class-123'));
        expect(student.currentReadingLevel, equals('Level 10'));
        expect(student.parentIds, contains('parent-123'));
        expect(student.parentIds, contains('parent-456'));
      });

      test('correctly parses stats object', () async {
        final firestore = TestHelpers.createFakeFirestore();
        await firestore.collection('students').doc('student-stats').set(testData);

        final doc = await firestore.collection('students').doc('student-stats').get();
        final student = StudentModel.fromFirestore(doc);

        expect(student.stats, isNotNull);
        expect(student.stats!.totalMinutesRead, equals(450));
        expect(student.stats!.totalBooksRead, equals(15));
        expect(student.stats!.currentStreak, equals(7));
        expect(student.stats!.longestStreak, equals(14));
        expect(student.stats!.averageMinutesPerDay, equals(25.0));
        expect(student.stats!.totalReadingDays, equals(18));
      });

      test('correctly parses reading level history', () async {
        final firestore = TestHelpers.createFakeFirestore();
        await firestore.collection('students').doc('student-history').set(testData);

        final doc = await firestore.collection('students').doc('student-history').get();
        final student = StudentModel.fromFirestore(doc);

        expect(student.readingLevelHistory, isNotEmpty);
        expect(student.readingLevelHistory.first.level, equals('Level 10'));
        expect(student.readingLevelHistory.first.setBy, equals('teacher-123'));
      });

      test('handles null optional fields', () async {
        final dataWithNulls = {
          ...testData,
          'stats': null,
          'readingLevelHistory': null,
        };

        final firestore = TestHelpers.createFakeFirestore();
        await firestore.collection('students').doc('student-nulls').set(dataWithNulls);

        final doc = await firestore.collection('students').doc('student-nulls').get();
        final student = StudentModel.fromFirestore(doc);

        expect(student.stats, isNull);
        expect(student.readingLevelHistory, isEmpty);
      });
    });

    group('toFirestore', () {
      test('converts student model to Firestore map', () {
        final student = StudentModel(
          id: 'student-convert',
          firstName: 'John',
          lastName: 'Doe',
          studentId: 'STU999',
          schoolId: 'school-999',
          classId: 'class-999',
          currentReadingLevel: 'Level 5',
          parentIds: ['parent-001'],
          stats: StudentStats(
            totalMinutesRead: 100,
            totalBooksRead: 5,
            currentStreak: 3,
            longestStreak: 5,
            averageMinutesPerDay: 20.0,
            totalReadingDays: 5,
            lastReadingDate: Timestamp.now(),
          ),
          readingLevelHistory: [
            ReadingLevelHistory(
              level: 'Level 5',
              date: Timestamp.now(),
              setBy: 'teacher-999',
            ),
          ],
          createdAt: Timestamp.now(),
          updatedAt: Timestamp.now(),
        );

        final map = student.toFirestore();

        expect(map['id'], equals('student-convert'));
        expect(map['firstName'], equals('John'));
        expect(map['lastName'], equals('Doe'));
        expect(map['studentId'], equals('STU999'));
        expect(map['currentReadingLevel'], equals('Level 5'));
        expect(map['parentIds'], contains('parent-001'));
        expect(map['stats'], isNotNull);
        expect(map['stats']['totalMinutesRead'], equals(100));
      });

      test('handles null stats in toFirestore', () {
        final student = StudentModel(
          id: 'student-no-stats',
          firstName: 'Jane',
          lastName: 'Smith',
          studentId: 'STU888',
          schoolId: 'school-888',
          classId: 'class-888',
          currentReadingLevel: 'Level 1',
          parentIds: [],
          stats: null,
          readingLevelHistory: [],
          createdAt: Timestamp.now(),
          updatedAt: Timestamp.now(),
        );

        final map = student.toFirestore();

        expect(map['stats'], isNull);
      });
    });

    group('copyWith', () {
      test('creates copy with updated fields', () {
        final original = StudentModel(
          id: 'student-original',
          firstName: 'Alice',
          lastName: 'Brown',
          studentId: 'STU777',
          schoolId: 'school-777',
          classId: 'class-777',
          currentReadingLevel: 'Level 8',
          parentIds: ['parent-111'],
          stats: StudentStats(
            totalMinutesRead: 200,
            totalBooksRead: 10,
            currentStreak: 5,
            longestStreak: 8,
            averageMinutesPerDay: 25.0,
            totalReadingDays: 8,
            lastReadingDate: Timestamp.now(),
          ),
          readingLevelHistory: [],
          createdAt: Timestamp.now(),
          updatedAt: Timestamp.now(),
        );

        final updated = original.copyWith(
          currentReadingLevel: 'Level 9',
          parentIds: ['parent-111', 'parent-222'],
        );

        expect(updated.id, equals(original.id));
        expect(updated.firstName, equals(original.firstName));
        expect(updated.currentReadingLevel, equals('Level 9')); // Changed
        expect(updated.parentIds.length, equals(2)); // Changed
        expect(updated.stats!.totalMinutesRead, equals(200)); // Unchanged
      });
    });

    group('StudentStats', () {
      test('calculates averages correctly', () {
        final stats = StudentStats(
          totalMinutesRead: 500,
          totalBooksRead: 20,
          currentStreak: 10,
          longestStreak: 15,
          averageMinutesPerDay: 25.0,
          totalReadingDays: 20,
          lastReadingDate: Timestamp.now(),
        );

        expect(stats.averageMinutesPerDay, equals(25.0));
        expect(stats.totalReadingDays, equals(20));
      });

      test('handles zero reading days', () {
        final stats = StudentStats(
          totalMinutesRead: 0,
          totalBooksRead: 0,
          currentStreak: 0,
          longestStreak: 0,
          averageMinutesPerDay: 0.0,
          totalReadingDays: 0,
          lastReadingDate: null,
        );

        expect(stats.averageMinutesPerDay, equals(0.0));
        expect(stats.totalReadingDays, equals(0));
        expect(stats.lastReadingDate, isNull);
      });

      test('streak logic makes sense', () {
        final stats = StudentStats(
          totalMinutesRead: 300,
          totalBooksRead: 12,
          currentStreak: 5,
          longestStreak: 10,
          averageMinutesPerDay: 20.0,
          totalReadingDays: 15,
          lastReadingDate: Timestamp.now(),
        );

        expect(stats.currentStreak, lessThanOrEqualTo(stats.longestStreak));
        expect(stats.currentStreak, lessThanOrEqualTo(stats.totalReadingDays));
      });
    });

    group('ReadingLevelHistory', () {
      test('records level changes chronologically', () {
        final history = [
          ReadingLevelHistory(
            level: 'Level 5',
            date: Timestamp.fromDate(DateTime(2024, 1, 1)),
            setBy: 'teacher-123',
          ),
          ReadingLevelHistory(
            level: 'Level 6',
            date: Timestamp.fromDate(DateTime(2024, 2, 1)),
            setBy: 'teacher-123',
          ),
          ReadingLevelHistory(
            level: 'Level 7',
            date: Timestamp.fromDate(DateTime(2024, 3, 1)),
            setBy: 'teacher-123',
          ),
        ];

        expect(history.length, equals(3));
        expect(history[0].level, equals('Level 5'));
        expect(history[1].level, equals('Level 6'));
        expect(history[2].level, equals('Level 7'));

        // Check chronological order
        expect(history[0].date.toDate().isBefore(history[1].date.toDate()), isTrue);
        expect(history[1].date.toDate().isBefore(history[2].date.toDate()), isTrue);
      });

      test('records who set the level', () {
        final history = ReadingLevelHistory(
          level: 'Level 10',
          date: Timestamp.now(),
          setBy: 'teacher-456',
        );

        expect(history.setBy, equals('teacher-456'));
      });
    });

    group('validation', () {
      test('student has required fields', () {
        final student = StudentModel(
          id: 'student-required',
          firstName: 'Test',
          lastName: 'Student',
          studentId: 'TEST001',
          schoolId: 'school-test',
          classId: 'class-test',
          currentReadingLevel: 'Level 1',
          parentIds: [],
          stats: null,
          readingLevelHistory: [],
          createdAt: Timestamp.now(),
          updatedAt: Timestamp.now(),
        );

        expect(student.id, isNotEmpty);
        expect(student.firstName, isNotEmpty);
        expect(student.lastName, isNotEmpty);
        expect(student.studentId, isNotEmpty);
        expect(student.schoolId, isNotEmpty);
        expect(student.classId, isNotEmpty);
        expect(student.currentReadingLevel, isNotEmpty);
      });

      test('parent IDs list can be empty', () {
        final student = StudentModel(
          id: 'student-no-parents',
          firstName: 'Orphan',
          lastName: 'Student',
          studentId: 'ORPHAN001',
          schoolId: 'school-test',
          classId: 'class-test',
          currentReadingLevel: 'Level 1',
          parentIds: [],
          stats: null,
          readingLevelHistory: [],
          createdAt: Timestamp.now(),
          updatedAt: Timestamp.now(),
        );

        expect(student.parentIds, isEmpty);
      });

      test('student can have multiple parents', () {
        final student = StudentModel(
          id: 'student-multi-parent',
          firstName: 'Multi',
          lastName: 'Parent',
          studentId: 'MULTI001',
          schoolId: 'school-test',
          classId: 'class-test',
          currentReadingLevel: 'Level 5',
          parentIds: ['parent-1', 'parent-2', 'parent-3'],
          stats: null,
          readingLevelHistory: [],
          createdAt: Timestamp.now(),
          updatedAt: Timestamp.now(),
        );

        expect(student.parentIds.length, equals(3));
      });
    });

    group('edge cases', () {
      test('handles very long names', () {
        final student = StudentModel(
          id: 'student-long-name',
          firstName: 'A' * 100,
          lastName: 'B' * 100,
          studentId: 'LONG001',
          schoolId: 'school-test',
          classId: 'class-test',
          currentReadingLevel: 'Level 1',
          parentIds: [],
          stats: null,
          readingLevelHistory: [],
          createdAt: Timestamp.now(),
          updatedAt: Timestamp.now(),
        );

        expect(student.firstName.length, equals(100));
        expect(student.lastName.length, equals(100));
      });

      test('handles special characters in names', () {
        final student = StudentModel(
          id: 'student-special',
          firstName: "O'Connor",
          lastName: 'Müller-Schmidt',
          studentId: 'SPEC001',
          schoolId: 'school-test',
          classId: 'class-test',
          currentReadingLevel: 'Level 1',
          parentIds: [],
          stats: null,
          readingLevelHistory: [],
          createdAt: Timestamp.now(),
          updatedAt: Timestamp.now(),
        );

        expect(student.firstName, equals("O'Connor"));
        expect(student.lastName, equals('Müller-Schmidt'));
      });

      test('handles extensive reading level history', () {
        final manyHistoryEntries = List.generate(
          50,
          (i) => ReadingLevelHistory(
            level: 'Level ${i + 1}',
            date: Timestamp.fromDate(DateTime(2024, 1, 1).add(Duration(days: i * 7))),
            setBy: 'teacher-123',
          ),
        );

        final student = StudentModel(
          id: 'student-history',
          firstName: 'Progress',
          lastName: 'Tracker',
          studentId: 'PROG001',
          schoolId: 'school-test',
          classId: 'class-test',
          currentReadingLevel: 'Level 50',
          parentIds: [],
          stats: null,
          readingLevelHistory: manyHistoryEntries,
          createdAt: Timestamp.now(),
          updatedAt: Timestamp.now(),
        );

        expect(student.readingLevelHistory.length, equals(50));
        expect(student.readingLevelHistory.first.level, equals('Level 1'));
        expect(student.readingLevelHistory.last.level, equals('Level 50'));
      });

      test('handles extreme stats values', () {
        final stats = StudentStats(
          totalMinutesRead: 100000, // ~1667 hours
          totalBooksRead: 1000,
          currentStreak: 365, // 1 year
          longestStreak: 500,
          averageMinutesPerDay: 274.0, // ~4.5 hours
          totalReadingDays: 365,
          lastReadingDate: Timestamp.now(),
        );

        expect(stats.totalMinutesRead, equals(100000));
        expect(stats.totalBooksRead, equals(1000));
        expect(stats.currentStreak, equals(365));
      });
    });
  });
}
