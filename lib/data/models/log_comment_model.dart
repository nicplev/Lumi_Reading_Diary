import 'package:cloud_firestore/cloud_firestore.dart';

/// Who authored a comment in a reading-log thread.
enum CommentAuthorRole {
  parent,
  teacher,
}

/// A single message in the threaded conversation attached to a reading log.
///
/// Stored at `schools/{schoolId}/readingLogs/{logId}/comments/{commentId}`.
/// `studentId` and `parentId` are denormalized from the parent log for display
/// and query convenience. Security rules load the parent log and require both
/// values to match before accepting a comment.
class LogCommentModel {
  final String id;
  final String authorId;
  final CommentAuthorRole authorRole;
  final String authorName;
  final String body;
  final DateTime createdAt;
  final String studentId;
  final String parentId;

  const LogCommentModel({
    required this.id,
    required this.authorId,
    required this.authorRole,
    required this.authorName,
    required this.body,
    required this.createdAt,
    required this.studentId,
    required this.parentId,
  });

  bool get isTeacher => authorRole == CommentAuthorRole.teacher;

  factory LogCommentModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return LogCommentModel(
      id: doc.id,
      authorId: data['authorId'] ?? '',
      authorRole: CommentAuthorRole.values.firstWhere(
        (e) => e.toString() == 'CommentAuthorRole.${data['authorRole']}',
        orElse: () => CommentAuthorRole.parent,
      ),
      authorName: data['authorName'] ?? '',
      body: data['body'] ?? '',
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      studentId: data['studentId'] ?? '',
      parentId: data['parentId'] ?? '',
    );
  }

  /// Firestore payload for a new comment.
  ///
  /// `createdAt` defaults to a server timestamp. Security rules require the
  /// trusted server receipt time for both online and offline-replayed comments.
  Map<String, dynamic> toFirestore({Object? createdAt}) {
    return {
      'authorId': authorId,
      'authorRole': authorRole.toString().split('.').last,
      'authorName': authorName,
      'body': body,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'studentId': studentId,
      'parentId': parentId,
    };
  }
}
