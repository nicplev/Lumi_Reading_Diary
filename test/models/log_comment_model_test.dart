import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/models/log_comment_model.dart';
import '../helpers/test_helpers.dart';

void main() {
  group('LogCommentModel', () {
    test('round-trips through Firestore with an explicit createdAt', () async {
      final firestore = TestHelpers.createFakeFirestore();
      final createdAt = DateTime(2026, 1, 2, 10, 30);
      final comment = LogCommentModel(
        id: 'c1',
        authorId: 'teacher-9',
        authorRole: CommentAuthorRole.teacher,
        authorName: 'Ms Smith',
        body: 'Lovely reading today!',
        createdAt: createdAt,
        studentId: 'student-1',
        parentId: 'parent-1',
      );

      await firestore.collection('comments').doc('c1').set(
            comment.toFirestore(createdAt: Timestamp.fromDate(createdAt)),
          );
      final doc = await firestore.collection('comments').doc('c1').get();
      final restored = LogCommentModel.fromFirestore(doc);

      expect(restored.id, 'c1');
      expect(restored.authorId, 'teacher-9');
      expect(restored.authorRole, CommentAuthorRole.teacher);
      expect(restored.isTeacher, isTrue);
      expect(restored.authorName, 'Ms Smith');
      expect(restored.body, 'Lovely reading today!');
      expect(restored.createdAt, createdAt);
      expect(restored.studentId, 'student-1');
      expect(restored.parentId, 'parent-1');
    });

    test('defaults createdAt to a server timestamp when not provided', () async {
      final firestore = TestHelpers.createFakeFirestore();
      final comment = LogCommentModel(
        id: 'c2',
        authorId: 'parent-1',
        authorRole: CommentAuthorRole.parent,
        authorName: 'Dad',
        body: 'Thank you!',
        createdAt: DateTime(2026, 1, 1),
        studentId: 'student-1',
        parentId: 'parent-1',
      );

      final payload = comment.toFirestore();
      expect(payload['createdAt'], isA<FieldValue>());

      await firestore.collection('comments').doc('c2').set(payload);
      final doc = await firestore.collection('comments').doc('c2').get();
      final restored = LogCommentModel.fromFirestore(doc);

      expect(restored.authorRole, CommentAuthorRole.parent);
      expect(restored.isTeacher, isFalse);
      expect(restored.createdAt, isNotNull);
    });

    test('unknown author role falls back to parent', () async {
      final firestore = TestHelpers.createFakeFirestore();
      await firestore.collection('comments').doc('weird').set({
        'authorId': 'x',
        'authorRole': 'headmaster',
        'authorName': 'X',
        'body': 'hi',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'studentId': 's',
        'parentId': 'p',
      });

      final doc = await firestore.collection('comments').doc('weird').get();
      final restored = LogCommentModel.fromFirestore(doc);

      expect(restored.authorRole, CommentAuthorRole.parent);
    });
  });
}
