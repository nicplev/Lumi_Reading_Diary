import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationCampaignModel {
  final String id;
  final String schoolId;
  final String title;
  final String body;
  final String messageType;
  final String audienceType;
  final List<String> targetClassIds;
  final List<String> targetStudentIds;
  final String status;
  final DateTime? scheduledFor;
  final DateTime? createdAt;
  final DateTime? sentAt;
  final String createdBy;
  final String createdByRole;
  final String createdByName;
  final int recipientParentCount;
  final int recipientStudentCount;
  final int inboxWrittenCount;
  final int pushSentCount;
  final int pushFailedCount;
  final String? errorSummary;

  const NotificationCampaignModel({
    required this.id,
    required this.schoolId,
    required this.title,
    required this.body,
    required this.messageType,
    required this.audienceType,
    required this.targetClassIds,
    required this.targetStudentIds,
    required this.status,
    required this.scheduledFor,
    required this.createdAt,
    required this.sentAt,
    required this.createdBy,
    required this.createdByRole,
    required this.createdByName,
    required this.recipientParentCount,
    required this.recipientStudentCount,
    required this.inboxWrittenCount,
    required this.pushSentCount,
    required this.pushFailedCount,
    required this.errorSummary,
  });

  factory NotificationCampaignModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final recipientCounts =
        data['recipientCounts'] as Map<String, dynamic>? ?? const {};
    final deliveryCounts =
        data['deliveryCounts'] as Map<String, dynamic>? ?? const {};

    return NotificationCampaignModel(
      id: doc.id,
      schoolId: data['schoolId'] as String? ?? '',
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      messageType: data['messageType'] as String? ?? 'general',
      audienceType: data['audienceType'] as String? ?? 'classes',
      targetClassIds: List<String>.from(data['targetClassIds'] ?? const []),
      targetStudentIds: List<String>.from(data['targetStudentIds'] ?? const []),
      status: data['status'] as String? ?? 'queued',
      scheduledFor: (data['scheduledFor'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      sentAt: (data['sentAt'] as Timestamp?)?.toDate(),
      createdBy: data['createdBy'] as String? ?? '',
      createdByRole: data['createdByRole'] as String? ?? '',
      createdByName: data['createdByName'] as String? ?? '',
      recipientParentCount: (recipientCounts['parents'] as num?)?.toInt() ?? 0,
      recipientStudentCount:
          (recipientCounts['students'] as num?)?.toInt() ?? 0,
      inboxWrittenCount: (deliveryCounts['inboxWritten'] as num?)?.toInt() ?? 0,
      pushSentCount: (deliveryCounts['pushSent'] as num?)?.toInt() ?? 0,
      pushFailedCount: (deliveryCounts['pushFailed'] as num?)?.toInt() ?? 0,
      errorSummary: data['errorSummary'] as String?,
    );
  }
}
