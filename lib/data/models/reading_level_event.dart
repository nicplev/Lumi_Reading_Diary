import 'package:cloud_firestore/cloud_firestore.dart';

class ReadingLevelEvent {
  final String id;
  final String studentId;
  final String schoolId;
  final String classId;
  final String? fromLevel;
  final String? toLevel;
  final int? fromLevelIndex;
  final int? toLevelIndex;
  final String? reason;
  final String source;
  final String changedByUserId;
  final String changedByRole;
  final String changedByName;
  final DateTime createdAt;

  const ReadingLevelEvent({
    required this.id,
    required this.studentId,
    required this.schoolId,
    required this.classId,
    this.fromLevel,
    this.toLevel,
    this.fromLevelIndex,
    this.toLevelIndex,
    this.reason,
    required this.source,
    required this.changedByUserId,
    required this.changedByRole,
    required this.changedByName,
    required this.createdAt,
  });

  factory ReadingLevelEvent.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ReadingLevelEvent(
      id: doc.id,
      studentId: data['studentId'] as String? ?? '',
      schoolId: data['schoolId'] as String? ?? '',
      classId: data['classId'] as String? ?? '',
      fromLevel: data['fromLevel'] as String?,
      toLevel: data['toLevel'] as String?,
      fromLevelIndex: (data['fromLevelIndex'] as num?)?.toInt(),
      toLevelIndex: (data['toLevelIndex'] as num?)?.toInt(),
      reason: data['reason'] as String?,
      source: data['source'] as String? ?? '',
      changedByUserId: data['changedByUserId'] as String? ?? '',
      changedByRole: data['changedByRole'] as String? ?? '',
      changedByName: data['changedByName'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'studentId': studentId,
      'schoolId': schoolId,
      'classId': classId,
      'fromLevel': fromLevel,
      'toLevel': toLevel,
      'fromLevelIndex': fromLevelIndex,
      'toLevelIndex': toLevelIndex,
      'reason': reason,
      'source': source,
      'changedByUserId': changedByUserId,
      'changedByRole': changedByRole,
      'changedByName': changedByName,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
