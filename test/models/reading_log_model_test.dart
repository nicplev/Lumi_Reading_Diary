import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/models/reading_log_model.dart';
import '../helpers/test_helpers.dart';

void main() {
  group('ReadingLogModel', () {
    late Map<String, dynamic> testData;
    late DateTime testDateTime;

    setUp(() {
      testDateTime = DateTime.now();
      testData = TestHelpers.sampleReadingLogData();
    });

    group('fromFirestore', () {
      test('creates model from Firestore document correctly', () async {
        final firestore = TestHelpers.createFakeFirestore();

        // Add document to fake Firestore
        await firestore
            .collection('readingLogs')
            .doc('test-log-123')
            .set(testData);

        // Get document
        final doc =
            await firestore.collection('readingLogs').doc('test-log-123').get();
        final log = ReadingLogModel.fromFirestore(doc);

        expect(log.id, equals('test-log-123'));
        expect(log.studentId, equals('test-student-123'));
        expect(log.parentId, equals('parent-123'));
        expect(log.minutesRead, equals(25));
        expect(log.targetMinutes, equals(20));
        expect(log.bookTitles, contains('Harry Potter'));
        expect(log.bookTitles, contains('The Hobbit'));
        expect(log.notes, equals('Great reading session!'));
        expect(log.status, equals(LogStatus.completed));
        expect(log.isOfflineCreated, equals(false));
      });

      test('handles null optional fields', () async {
        final dataWithNulls = {
          ...testData,
          'notes': null,
          'photoUrls': null,
          'syncedAt': null,
        };

        final firestore = TestHelpers.createFakeFirestore();
        await firestore
            .collection('readingLogs')
            .doc('test-log-456')
            .set(dataWithNulls);

        final doc =
            await firestore.collection('readingLogs').doc('test-log-456').get();
        final log = ReadingLogModel.fromFirestore(doc);

        expect(log.notes, isNull);
        expect(log.photoUrls, isNull);
        expect(log.syncedAt, isNull);
      });

      test('correctly parses status enum', () async {
        final statuses = ['completed', 'partial', 'skipped', 'pending'];

        for (final status in statuses) {
          final data = {...testData, 'status': status};
          final firestore = TestHelpers.createFakeFirestore();
          await firestore
              .collection('readingLogs')
              .doc('log-$status')
              .set(data);

          final doc = await firestore
              .collection('readingLogs')
              .doc('log-$status')
              .get();
          final log = ReadingLogModel.fromFirestore(doc);
          expect(log.status.toString(), contains(status));
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
          classId: 'class-789',
          date: testDateTime,
          minutesRead: 30,
          targetMinutes: 25,
          bookTitles: ['Book One', 'Book Two'],
          notes: 'Test notes',
          status: LogStatus.completed,
          photoUrls: ['https://example.com/photo.jpg'],
          isOfflineCreated: false,
          syncedAt: testDateTime,
          createdAt: testDateTime,
        );

        final map = log.toFirestore();

        expect(map['studentId'], equals('student-789'));
        expect(map['parentId'], equals('parent-789'));
        expect(map['schoolId'], equals('school-789'));
        expect(map['classId'], equals('class-789'));
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
          classId: 'class-123',
          date: testDateTime,
          minutesRead: 20,
          targetMinutes: 20,
          bookTitles: [],
          notes: null,
          status: LogStatus.pending,
          photoUrls: null,
          isOfflineCreated: true,
          syncedAt: null,
          createdAt: testDateTime,
        );

        final map = log.toFirestore();

        expect(map['notes'], isNull);
        expect(map['photoUrls'], isNull);
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
          classId: 'class-123',
          date: testDateTime,
          minutesRead: 20,
          targetMinutes: 20,
          bookTitles: ['Local Book'],
          notes: 'Local notes',
          status: LogStatus.completed,
          photoUrls: null,
          isOfflineCreated: true,
          syncedAt: null,
          createdAt: testDateTime,
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
          'classId': 'class-456',
          'date': DateTime.now().toIso8601String(),
          'minutesRead': 15,
          'targetMinutes': 20,
          'bookTitles': ['Book A', 'Book B'],
          'notes': 'From local',
          'status': 'partial',
          'photoUrls': null,
          'isOfflineCreated': true,
          'syncedAt': null,
          'createdAt': DateTime.now().toIso8601String(),
        };

        final log = ReadingLogModel.fromLocal(localData);

        expect(log.id, equals('local-log-456'));
        expect(log.minutesRead, equals(15));
        expect(log.status, equals(LogStatus.partial));
        expect(log.isOfflineCreated, equals(true));
      });

      test('round-trip conversion preserves data', () {
        final original = ReadingLogModel(
          id: 'roundtrip-log',
          studentId: 'student-rt',
          parentId: 'parent-rt',
          schoolId: 'school-rt',
          classId: 'class-rt',
          date: testDateTime,
          minutesRead: 25,
          targetMinutes: 20,
          bookTitles: ['Book X', 'Book Y', 'Book Z'],
          notes: 'Roundtrip test',
          status: LogStatus.completed,
          photoUrls: ['https://example.com/photo.jpg'],
          isOfflineCreated: false,
          syncedAt: testDateTime,
          createdAt: testDateTime,
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
          classId: 'class-copy',
          date: testDateTime,
          minutesRead: 20,
          targetMinutes: 20,
          bookTitles: ['Original Book'],
          notes: 'Original notes',
          status: LogStatus.pending,
          photoUrls: null,
          isOfflineCreated: true,
          syncedAt: null,
          createdAt: testDateTime,
        );

        final updated = original.copyWith(
          minutesRead: 30,
          status: LogStatus.completed,
          isOfflineCreated: false,
          syncedAt: testDateTime,
        );

        expect(updated.id, equals(original.id));
        expect(updated.studentId, equals(original.studentId));
        expect(updated.minutesRead, equals(30)); // Changed
        expect(updated.status, equals(LogStatus.completed)); // Changed
        expect(updated.isOfflineCreated, equals(false)); // Changed
        expect(updated.syncedAt, equals(testDateTime)); // Changed
        expect(updated.notes, equals(original.notes)); // Unchanged
      });

      test('copyWith null parameters keeps original values', () {
        final original = ReadingLogModel(
          id: 'keep-log',
          studentId: 'student-keep',
          parentId: 'parent-keep',
          schoolId: 'school-keep',
          classId: 'class-keep',
          date: testDateTime,
          minutesRead: 20,
          targetMinutes: 20,
          bookTitles: ['Keep Book'],
          notes: 'Keep notes',
          status: LogStatus.completed,
          photoUrls: null,
          isOfflineCreated: false,
          syncedAt: testDateTime,
          createdAt: testDateTime,
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
          classId: 'class-123',
          date: testDateTime,
          minutesRead: 25,
          targetMinutes: 20,
          bookTitles: [],
          notes: null,
          status: LogStatus.completed,
          photoUrls: null,
          isOfflineCreated: false,
          syncedAt: null,
          createdAt: testDateTime,
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
          classId: 'class-123',
          date: testDateTime,
          minutesRead: 25,
          targetMinutes: 20,
          bookTitles: ['Book'],
          notes: null,
          status: LogStatus.completed,
          photoUrls: null,
          isOfflineCreated: false,
          syncedAt: null,
          createdAt: testDateTime,
        );

        expect(log.status, equals(LogStatus.completed));
        expect(log.minutesRead, greaterThan(0));
      });
    });

    group('ReadingFeeling and parent comment', () {
      test('childFeeling serializes and deserializes via local storage', () {
        final log = ReadingLogModel(
          id: 'feeling-log',
          studentId: 'student-1',
          parentId: 'parent-1',
          schoolId: 'school-1',
          classId: 'class-1',
          date: testDateTime,
          minutesRead: 20,
          targetMinutes: 20,
          bookTitles: ['Test Book'],
          status: LogStatus.completed,
          createdAt: testDateTime,
          childFeeling: ReadingFeeling.great,
          parentComment: 'Great job!',
        );

        final localMap = log.toLocal();
        expect(localMap['childFeeling'], equals('great'));
        expect(localMap['parentComment'], equals('Great job!'));

        final restored = ReadingLogModel.fromLocal(localMap);
        expect(restored.childFeeling, equals(ReadingFeeling.great));
        expect(restored.parentComment, equals('Great job!'));
      });

      test('childFeeling serializes and deserializes via Firestore', () async {
        final firestore = TestHelpers.createFakeFirestore();
        final log = ReadingLogModel(
          id: 'feeling-firestore',
          studentId: 'student-1',
          parentId: 'parent-1',
          schoolId: 'school-1',
          classId: 'class-1',
          date: testDateTime,
          minutesRead: 20,
          targetMinutes: 20,
          bookTitles: ['Test Book'],
          status: LogStatus.completed,
          createdAt: testDateTime,
          childFeeling: ReadingFeeling.tricky,
          parentComment: 'Sounded out words well',
        );

        await firestore
            .collection('readingLogs')
            .doc(log.id)
            .set(log.toFirestore());

        final doc = await firestore.collection('readingLogs').doc(log.id).get();
        final restored = ReadingLogModel.fromFirestore(doc);

        expect(restored.childFeeling, equals(ReadingFeeling.tricky));
        expect(restored.parentComment, equals('Sounded out words well'));
      });

      test('null childFeeling is handled correctly', () {
        final log = ReadingLogModel(
          id: 'no-feeling-log',
          studentId: 'student-1',
          parentId: 'parent-1',
          schoolId: 'school-1',
          classId: 'class-1',
          date: testDateTime,
          minutesRead: 20,
          targetMinutes: 20,
          bookTitles: [],
          status: LogStatus.completed,
          createdAt: testDateTime,
          childFeeling: null,
          parentComment: null,
        );

        final map = log.toFirestore();
        expect(map['childFeeling'], isNull);
        expect(map['parentComment'], isNull);
      });

      test('all ReadingFeeling values roundtrip through local storage', () {
        for (final feeling in ReadingFeeling.values) {
          final log = ReadingLogModel(
            id: 'feeling-${feeling.name}',
            studentId: 'student-1',
            parentId: 'parent-1',
            schoolId: 'school-1',
            classId: 'class-1',
            date: testDateTime,
            minutesRead: 20,
            targetMinutes: 20,
            bookTitles: [],
            status: LogStatus.completed,
            createdAt: testDateTime,
            childFeeling: feeling,
          );

          final localMap = log.toLocal();
          final restored = ReadingLogModel.fromLocal(localMap);
          expect(restored.childFeeling, equals(feeling),
              reason: 'Failed roundtrip for ${feeling.name}');
        }
      });

      test('copyWith updates childFeeling and parentComment', () {
        final original = ReadingLogModel(
          id: 'copy-feeling',
          studentId: 'student-1',
          parentId: 'parent-1',
          schoolId: 'school-1',
          classId: 'class-1',
          date: testDateTime,
          minutesRead: 20,
          targetMinutes: 20,
          bookTitles: [],
          status: LogStatus.completed,
          createdAt: testDateTime,
          childFeeling: ReadingFeeling.okay,
          parentComment: 'Original comment',
        );

        final updated = original.copyWith(
          childFeeling: ReadingFeeling.great,
          parentComment: 'Updated comment',
        );

        expect(updated.childFeeling, equals(ReadingFeeling.great));
        expect(updated.parentComment, equals('Updated comment'));
        expect(updated.id, equals(original.id));
      });

      test('ReadingFeeling enum has 5 values', () {
        expect(ReadingFeeling.values.length, equals(5));
        expect(ReadingFeeling.values, contains(ReadingFeeling.hard));
        expect(ReadingFeeling.values, contains(ReadingFeeling.tricky));
        expect(ReadingFeeling.values, contains(ReadingFeeling.okay));
        expect(ReadingFeeling.values, contains(ReadingFeeling.good));
        expect(ReadingFeeling.values, contains(ReadingFeeling.great));
      });
    });

    group('edge cases', () {
      test('handles empty book titles list', () {
        final log = ReadingLogModel(
          id: 'empty-books-log',
          studentId: 'student-123',
          parentId: 'parent-123',
          schoolId: 'school-123',
          classId: 'class-123',
          date: testDateTime,
          minutesRead: 20,
          targetMinutes: 20,
          bookTitles: [],
          notes: null,
          status: LogStatus.completed,
          photoUrls: null,
          isOfflineCreated: false,
          syncedAt: null,
          createdAt: testDateTime,
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
          classId: 'class-123',
          date: testDateTime,
          minutesRead: 20,
          targetMinutes: 20,
          bookTitles: [],
          notes: longNotes,
          status: LogStatus.completed,
          photoUrls: null,
          isOfflineCreated: false,
          syncedAt: null,
          createdAt: testDateTime,
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
          classId: 'class-123',
          date: testDateTime,
          minutesRead: 60,
          targetMinutes: 20,
          bookTitles: manyBooks,
          notes: null,
          status: LogStatus.completed,
          photoUrls: null,
          isOfflineCreated: false,
          syncedAt: null,
          createdAt: testDateTime,
        );

        expect(log.bookTitles.length, equals(20));
        expect(log.bookTitles.first, equals('Book 1'));
        expect(log.bookTitles.last, equals('Book 20'));
      });
    });

    group('comment thread denormalization', () {
      ReadingLogModel buildLog({
        DateTime? lastCommentAt,
        String? lastCommentByRole,
        Map<String, DateTime> commentsViewedAt = const {},
      }) {
        return ReadingLogModel(
          id: 'thread-log',
          studentId: 'student-1',
          parentId: 'parent-1',
          schoolId: 'school-1',
          classId: 'class-1',
          date: testDateTime,
          minutesRead: 20,
          targetMinutes: 20,
          bookTitles: const ['Book'],
          status: LogStatus.completed,
          createdAt: testDateTime,
          lastCommentPreview: 'See you tomorrow',
          lastCommentAt: lastCommentAt,
          lastCommentByRole: lastCommentByRole,
          commentsViewedAt: commentsViewedAt,
        );
      }

      test('round-trips through Firestore', () async {
        final firestore = TestHelpers.createFakeFirestore();
        final viewed = DateTime(2026, 1, 2, 9);
        final lastAt = DateTime(2026, 1, 2, 10);
        final log = buildLog(
          lastCommentAt: lastAt,
          lastCommentByRole: 'teacher',
          commentsViewedAt: {'parent-1': viewed},
        );

        await firestore
            .collection('readingLogs')
            .doc(log.id)
            .set(log.toFirestore());
        final doc = await firestore.collection('readingLogs').doc(log.id).get();
        final restored = ReadingLogModel.fromFirestore(doc);

        expect(restored.lastCommentPreview, equals('See you tomorrow'));
        expect(restored.lastCommentByRole, equals('teacher'));
        expect(restored.lastCommentAt, equals(lastAt));
        expect(restored.commentsViewedAt['parent-1'], equals(viewed));
      });

      test('round-trips through local storage', () {
        final viewed = DateTime(2026, 1, 2, 9);
        final lastAt = DateTime(2026, 1, 2, 10);
        final log = buildLog(
          lastCommentAt: lastAt,
          lastCommentByRole: 'parent',
          commentsViewedAt: {'teacher-9': viewed},
        );

        final restored = ReadingLogModel.fromLocal(log.toLocal());

        expect(restored.lastCommentByRole, equals('parent'));
        expect(restored.lastCommentAt, equals(lastAt));
        expect(restored.commentsViewedAt['teacher-9'], equals(viewed));
      });

      test('accepts Hive maps whose key/value types are dynamic', () {
        final viewed = DateTime(2026, 1, 2, 9);
        final local = buildLog(
          commentsViewedAt: {'teacher-9': viewed},
        ).toLocal();
        local['commentsViewedAt'] = <dynamic, dynamic>{
          'teacher-9': viewed.toIso8601String(),
        };
        local['metadata'] = <dynamic, dynamic>{'quickLog': false};

        final restored = ReadingLogModel.fromLocal(local);

        expect(restored.commentsViewedAt['teacher-9'], equals(viewed));
        expect(restored.metadata, equals({'quickLog': false}));
      });

      test('ignores malformed local comment-view markers', () {
        final local = buildLog().toLocal();
        local['commentsViewedAt'] = <dynamic, dynamic>{
          7: '2026-01-02T09:00:00.000',
          'bad-date': 'not-a-date',
          'bad-value': 123,
        };

        final restored = ReadingLogModel.fromLocal(local);

        expect(restored.commentsViewedAt, isEmpty);
      });

      test('hasUnreadFor truth table', () {
        final lastAt = DateTime(2026, 1, 2, 10);

        // No thread yet → nothing unread.
        expect(buildLog().hasUnreadFor('parent-1', 'parent'), isFalse);

        // Newest comment is my own → not unread.
        expect(
          buildLog(lastCommentAt: lastAt, lastCommentByRole: 'parent')
              .hasUnreadFor('parent-1', 'parent'),
          isFalse,
        );

        // Other party commented, never viewed → unread.
        expect(
          buildLog(lastCommentAt: lastAt, lastCommentByRole: 'teacher')
              .hasUnreadFor('parent-1', 'parent'),
          isTrue,
        );

        // Viewed before the latest comment → still unread.
        expect(
          buildLog(
            lastCommentAt: lastAt,
            lastCommentByRole: 'teacher',
            commentsViewedAt: {
              'parent-1': lastAt.subtract(const Duration(hours: 1))
            },
          ).hasUnreadFor('parent-1', 'parent'),
          isTrue,
        );

        // Viewed after the latest comment → read.
        expect(
          buildLog(
            lastCommentAt: lastAt,
            lastCommentByRole: 'teacher',
            commentsViewedAt: {
              'parent-1': lastAt.add(const Duration(minutes: 1))
            },
          ).hasUnreadFor('parent-1', 'parent'),
          isFalse,
        );
      });
    });

    group('shared comprehension review state', () {
      test('is reviewed only for the current audio generation', () async {
        final firestore = TestHelpers.createFakeFirestore();
        testData.addAll({
          'comprehensionAudioUploaded': true,
          'comprehensionAudioPath':
              'schools/school-1/comprehension_audio/log-1.m4a',
          'comprehensionAudioObjectGeneration': 'generation-2',
          'comprehensionAudioReviewStatus': 'reviewed',
          'comprehensionAudioReviewedGeneration': 'generation-2',
        });
        await firestore.collection('readingLogs').doc('log-1').set(testData);
        final doc =
            await firestore.collection('readingLogs').doc('log-1').get();

        expect(
          ReadingLogModel.fromFirestore(doc).isComprehensionAudioReviewed,
          isTrue,
        );

        await doc.reference.update({
          'comprehensionAudioObjectGeneration': 'generation-3',
        });
        final replaced = await doc.reference.get();
        expect(
          ReadingLogModel.fromFirestore(replaced).isComprehensionAudioReviewed,
          isFalse,
        );
      });

      test('legacy recording without review fields remains pending', () async {
        final firestore = TestHelpers.createFakeFirestore();
        testData.addAll({
          'comprehensionAudioUploaded': true,
          'comprehensionAudioPath':
              'schools/school-1/comprehension_audio/log-legacy.m4a',
          'comprehensionAudioObjectGeneration': 'generation-1',
        });
        await firestore
            .collection('readingLogs')
            .doc('log-legacy')
            .set(testData);
        final doc =
            await firestore.collection('readingLogs').doc('log-legacy').get();

        expect(
          ReadingLogModel.fromFirestore(doc).isComprehensionAudioReviewed,
          isFalse,
        );
      });
    });
  });
}
