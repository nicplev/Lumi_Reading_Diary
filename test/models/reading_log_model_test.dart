import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/models/reading_log_model.dart';
import '../helpers/test_helpers.dart';

void main() {
  group('ReadingLogModel', () {
    late Map<String, dynamic> testData;
    late Timestamp testTimestamp;

    setUp(() {
      testTimestamp = Timestamp.now();
      testData = TestHelpers.sampleReadingLogData();
    });

    group('fromFirestore', () {
      test('creates model from Firestore document correctly', () {
        final firestore = TestHelpers.createFakeFirestore();

        // Add document to fake Firestore
        firestore.collection('readingLogs').doc('test-log-123').set(testData);

        // Get document
        final docFuture = firestore.collection('readingLogs').doc('test-log-123').get();

        docFuture.then((doc) {
          final log = ReadingLogModel.fromFirestore(doc);

          expect(log.id, equals('test-log-123'));
          expect(log.studentId, equals('test-student-123'));
          expect(log.parentId, equals('parent-123'));
          expect(log.minutesRead, equals(25));
          expect(log.targetMinutes, equals(20));
          expect(log.bookTitles, contains('Harry Potter'));
          expect(log.bookTitles, contains('The Hobbit'));
          expect(log.notes, equals('Great reading session!'));
          expect(log.status, equals(ReadingStatus.completed));
          expect(log.isOfflineCreated, equals(false));
        });
      });

      test('handles null optional fields', () {
        final dataWithNulls = {
          ...testData,
          'notes': null,
          'photoUrl': null,
          'syncedAt': null,
        };

        final firestore = TestHelpers.createFakeFirestore();
        firestore.collection('readingLogs').doc('test-log-456').set(dataWithNulls);

        final docFuture = firestore.collection('readingLogs').doc('test-log-456').get();

        docFuture.then((doc) {
          final log = ReadingLogModel.fromFirestore(doc);

          expect(log.notes, isNull);
          expect(log.photoUrl, isNull);
          expect(log.syncedAt, isNull);
        });
      });

      test('correctly parses status enum', () {
        final statuses = ['completed', 'partial', 'skipped', 'pending'];

        for (final status in statuses) {
          final data = {...testData, 'status': status};
          final firestore = TestHelpers.createFakeFirestore();
          firestore.collection('readingLogs').doc('log-$status').set(data);

          final docFuture = firestore.collection('readingLogs').doc('log-$status').get();

          docFuture.then((doc) {
            final log = ReadingLogModel.fromFirestore(doc);
            expect(log.status.toString(), contains(status));
          });
        }
      });
    });

    group('toFirestore', () {
      test('converts model to Firestore map correctly', () {
        final log = ReadingLogModel(
          id: 'test-log-789',
          studentId: 'student-789',
          parentId: 'parent-789',
          schoolId: 'school-789',
          date: testTimestamp,
          minutesRead: 30,
          targetMinutes: 25,
          bookTitles: ['Book One', 'Book Two'],
          notes: 'Test notes',
          status: ReadingStatus.completed,
          photoUrl: 'https://example.com/photo.jpg',
          isOfflineCreated: false,
          syncedAt: testTimestamp,
          createdAt: testTimestamp,
          updatedAt: testTimestamp,
        );

        final map = log.toFirestore();

        expect(map['id'], equals('test-log-789'));
        expect(map['studentId'], equals('student-789'));
        expect(map['parentId'], equals('parent-789'));
        expect(map['schoolId'], equals('school-789'));
        expect(map['minutesRead'], equals(30));
        expect(map['targetMinutes'], equals(25));
        expect(map['bookTitles'], equals(['Book One', 'Book Two']));
        expect(map['notes'], equals('Test notes'));
        expect(map['status'], equals('completed'));
        expect(map['isOfflineCreated'], equals(false));
      });

      test('handles null values in toFirestore', () {
        final log = ReadingLogModel(
          id: 'test-log-null',
          studentId: 'student-123',
          parentId: 'parent-123',
          schoolId: 'school-123',
          date: testTimestamp,
          minutesRead: 20,
          targetMinutes: 20,
          bookTitles: [],
          notes: null,
          status: ReadingStatus.pending,
          photoUrl: null,
          isOfflineCreated: true,
          syncedAt: null,
          createdAt: testTimestamp,
          updatedAt: testTimestamp,
        );

        final map = log.toFirestore();

        expect(map['notes'], isNull);
        expect(map['photoUrl'], isNull);
        expect(map['syncedAt'], isNull);
      });
    });

    group('toLocal and fromLocal', () {
      test('converts to local storage format', () {
        final log = ReadingLogModel(
          id: 'local-log-123',
          studentId: 'student-123',
          parentId: 'parent-123',
          schoolId: 'school-123',
          date: testTimestamp,
          minutesRead: 20,
          targetMinutes: 20,
          bookTitles: ['Local Book'],
          notes: 'Local notes',
          status: ReadingStatus.completed,
          photoUrl: null,
          isOfflineCreated: true,
          syncedAt: null,
          createdAt: testTimestamp,
          updatedAt: testTimestamp,
        );

        final localMap = log.toLocal();

        expect(localMap['id'], equals('local-log-123'));
        expect(localMap['date'], isA<String>()); // Should be ISO string
        expect(localMap['isOfflineCreated'], equals(true));
      });

      test('converts from local storage format', () {
        final localData = {
          'id': 'local-log-456',
          'studentId': 'student-456',
          'parentId': 'parent-456',
          'schoolId': 'school-456',
          'date': DateTime.now().toIso8601String(),
          'minutesRead': 15,
          'targetMinutes': 20,
          'bookTitles': ['Book A', 'Book B'],
          'notes': 'From local',
          'status': 'partial',
          'photoUrl': null,
          'isOfflineCreated': true,
          'syncedAt': null,
          'createdAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        };

        final log = ReadingLogModel.fromLocal(localData);

        expect(log.id, equals('local-log-456'));
        expect(log.minutesRead, equals(15));
        expect(log.status, equals(ReadingStatus.partial));
        expect(log.isOfflineCreated, equals(true));
      });

      test('round-trip conversion preserves data', () {
        final original = ReadingLogModel(
          id: 'roundtrip-log',
          studentId: 'student-rt',
          parentId: 'parent-rt',
          schoolId: 'school-rt',
          date: testTimestamp,
          minutesRead: 25,
          targetMinutes: 20,
          bookTitles: ['Book X', 'Book Y', 'Book Z'],
          notes: 'Roundtrip test',
          status: ReadingStatus.completed,
          photoUrl: 'https://example.com/photo.jpg',
          isOfflineCreated: false,
          syncedAt: testTimestamp,
          createdAt: testTimestamp,
          updatedAt: testTimestamp,
        );

        final localMap = original.toLocal();
        final restored = ReadingLogModel.fromLocal(localMap);

        expect(restored.id, equals(original.id));
        expect(restored.studentId, equals(original.studentId));
        expect(restored.minutesRead, equals(original.minutesRead));
        expect(restored.bookTitles.length, equals(original.bookTitles.length));
        expect(restored.notes, equals(original.notes));
        expect(restored.status, equals(original.status));
      });
    });

    group('copyWith', () {
      test('creates copy with updated fields', () {
        final original = ReadingLogModel(
          id: 'copy-log',
          studentId: 'student-copy',
          parentId: 'parent-copy',
          schoolId: 'school-copy',
          date: testTimestamp,
          minutesRead: 20,
          targetMinutes: 20,
          bookTitles: ['Original Book'],
          notes: 'Original notes',
          status: ReadingStatus.pending,
          photoUrl: null,
          isOfflineCreated: true,
          syncedAt: null,
          createdAt: testTimestamp,
          updatedAt: testTimestamp,
        );

        final updated = original.copyWith(
          minutesRead: 30,
          status: ReadingStatus.completed,
          isOfflineCreated: false,
          syncedAt: testTimestamp,
        );

        expect(updated.id, equals(original.id));
        expect(updated.studentId, equals(original.studentId));
        expect(updated.minutesRead, equals(30)); // Changed
        expect(updated.status, equals(ReadingStatus.completed)); // Changed
        expect(updated.isOfflineCreated, equals(false)); // Changed
        expect(updated.syncedAt, equals(testTimestamp)); // Changed
        expect(updated.notes, equals(original.notes)); // Unchanged
      });

      test('copyWith null parameters keeps original values', () {
        final original = ReadingLogModel(
          id: 'keep-log',
          studentId: 'student-keep',
          parentId: 'parent-keep',
          schoolId: 'school-keep',
          date: testTimestamp,
          minutesRead: 20,
          targetMinutes: 20,
          bookTitles: ['Keep Book'],
          notes: 'Keep notes',
          status: ReadingStatus.completed,
          photoUrl: null,
          isOfflineCreated: false,
          syncedAt: testTimestamp,
          createdAt: testTimestamp,
          updatedAt: testTimestamp,
        );

        final copy = original.copyWith();

        expect(copy.id, equals(original.id));
        expect(copy.minutesRead, equals(original.minutesRead));
        expect(copy.status, equals(original.status));
        expect(copy.notes, equals(original.notes));
      });
    });

    group('validation', () {
      test('reading log has valid minutes range', () {
        final log = ReadingLogModel(
          id: 'valid-log',
          studentId: 'student-123',
          parentId: 'parent-123',
          schoolId: 'school-123',
          date: testTimestamp,
          minutesRead: 25,
          targetMinutes: 20,
          bookTitles: [],
          notes: null,
          status: ReadingStatus.completed,
          photoUrl: null,
          isOfflineCreated: false,
          syncedAt: null,
          createdAt: testTimestamp,
          updatedAt: testTimestamp,
        );

        expect(log.minutesRead, greaterThan(0));
        expect(log.minutesRead, lessThan(300)); // Reasonable max
      });

      test('completed status has minutes read', () {
        final log = ReadingLogModel(
          id: 'completed-log',
          studentId: 'student-123',
          parentId: 'parent-123',
          schoolId: 'school-123',
          date: testTimestamp,
          minutesRead: 25,
          targetMinutes: 20,
          bookTitles: ['Book'],
          notes: null,
          status: ReadingStatus.completed,
          photoUrl: null,
          isOfflineCreated: false,
          syncedAt: null,
          createdAt: testTimestamp,
          updatedAt: testTimestamp,
        );

        expect(log.status, equals(ReadingStatus.completed));
        expect(log.minutesRead, greaterThan(0));
      });
    });

    group('edge cases', () {
      test('handles empty book titles list', () {
        final log = ReadingLogModel(
          id: 'empty-books-log',
          studentId: 'student-123',
          parentId: 'parent-123',
          schoolId: 'school-123',
          date: testTimestamp,
          minutesRead: 20,
          targetMinutes: 20,
          bookTitles: [],
          notes: null,
          status: ReadingStatus.completed,
          photoUrl: null,
          isOfflineCreated: false,
          syncedAt: null,
          createdAt: testTimestamp,
          updatedAt: testTimestamp,
        );

        expect(log.bookTitles, isEmpty);
        final map = log.toFirestore();
        expect(map['bookTitles'], isEmpty);
      });

      test('handles very long notes', () {
        final longNotes = 'A' * 1000; // 1000 characters
        final log = ReadingLogModel(
          id: 'long-notes-log',
          studentId: 'student-123',
          parentId: 'parent-123',
          schoolId: 'school-123',
          date: testTimestamp,
          minutesRead: 20,
          targetMinutes: 20,
          bookTitles: [],
          notes: longNotes,
          status: ReadingStatus.completed,
          photoUrl: null,
          isOfflineCreated: false,
          syncedAt: null,
          createdAt: testTimestamp,
          updatedAt: testTimestamp,
        );

        expect(log.notes, equals(longNotes));
        expect(log.notes!.length, equals(1000));
      });

      test('handles many book titles', () {
        final manyBooks = List.generate(20, (i) => 'Book ${i + 1}');
        final log = ReadingLogModel(
          id: 'many-books-log',
          studentId: 'student-123',
          parentId: 'parent-123',
          schoolId: 'school-123',
          date: testTimestamp,
          minutesRead: 60,
          targetMinutes: 20,
          bookTitles: manyBooks,
          notes: null,
          status: ReadingStatus.completed,
          photoUrl: null,
          isOfflineCreated: false,
          syncedAt: null,
          createdAt: testTimestamp,
          updatedAt: testTimestamp,
        );

        expect(log.bookTitles.length, equals(20));
        expect(log.bookTitles.first, equals('Book 1'));
        expect(log.bookTitles.last, equals('Book 20'));
      });
    });
  });
}
