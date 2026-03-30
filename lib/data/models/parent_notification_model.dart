import 'package:cloud_firestore/cloud_firestore.dart';

class ParentNotificationModel {
  final String id;
  final String campaignId;
  final String schoolId;
  final String title;
  final String body;
  final String messageType;
  final List<String> studentIds;
  final List<String> classIds;
  final String senderName;
  final String senderRole;
  final String pushStatus;
  final bool isRead;
  final DateTime? readAt;
  final DateTime? createdAt;
  final DateTime? deliveredAt;

  const ParentNotificationModel({
    required this.id,
    required this.campaignId,
    required this.schoolId,
    required this.title,
    required this.body,
    required this.messageType,
    required this.studentIds,
    required this.classIds,
    required this.senderName,
    required this.senderRole,
    required this.pushStatus,
    required this.isRead,
    required this.readAt,
    required this.createdAt,
    required this.deliveredAt,
  });

  factory ParentNotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ParentNotificationModel(
      id: doc.id,
      campaignId: data['campaignId'] as String? ?? '',
      schoolId: data['schoolId'] as String? ?? '',
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      messageType: data['messageType'] as String? ?? 'general',
      studentIds: List<String>.from(data['studentIds'] ?? const []),
      classIds: List<String>.from(data['classIds'] ?? const []),
      senderName: data['senderName'] as String? ?? '',
      senderRole: data['senderRole'] as String? ?? '',
      pushStatus: data['pushStatus'] as String? ?? 'pending',
      isRead: data['isRead'] as bool? ?? false,
      readAt: (data['readAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      deliveredAt: (data['deliveredAt'] as Timestamp?)?.toDate(),
    );
  }
}
