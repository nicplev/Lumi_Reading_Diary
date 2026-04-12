import 'package:cloud_firestore/cloud_firestore.dart';

class OnboardingEmailRecord {
  final String id;
  final String status;
  final DateTime createdAt;
  final String createdBy;
  final DateTime? sentAt;
  final String? emailSubject;
  final String? customMessage;
  final int? recipientCount;
  final Map<String, int>? deliveryCounts;
  final String? errorSummary;

  OnboardingEmailRecord({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.createdBy,
    this.sentAt,
    this.emailSubject,
    this.customMessage,
    this.recipientCount,
    this.deliveryCounts,
    this.errorSummary,
  });

  factory OnboardingEmailRecord.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final counts = data['deliveryCounts'] as Map<String, dynamic>?;
    return OnboardingEmailRecord(
      id: doc.id,
      status: data['status'] ?? 'queued',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: data['createdBy'] ?? '',
      sentAt: (data['sentAt'] as Timestamp?)?.toDate(),
      emailSubject: data['emailSubject'],
      customMessage: data['customMessage'],
      recipientCount: data['recipientCount'],
      deliveryCounts: counts != null
          ? {
              'sent': (counts['sent'] as num?)?.toInt() ?? 0,
              'failed': (counts['failed'] as num?)?.toInt() ?? 0,
              'skipped': (counts['skipped'] as num?)?.toInt() ?? 0,
            }
          : null,
      errorSummary: data['errorSummary'],
    );
  }
}

class ParentOnboardingEmailService {
  final FirebaseFirestore _firestore;

  ParentOnboardingEmailService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Queue an onboarding email batch for processing by Cloud Function
  Future<String> sendOnboardingEmails({
    required String schoolId,
    required List<String> studentIds,
    required String createdBy,
    String? emailSubject,
    String? customMessage,
    bool generateMissingCodes = true,
  }) async {
    final docRef = _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('parentOnboardingEmails')
        .doc();

    await docRef.set({
      'schoolId': schoolId,
      'status': 'queued',
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
      'targetStudentIds': studentIds,
      'emailSubject': emailSubject,
      'customMessage': customMessage,
      'generateMissingCodes': generateMissingCodes,
    });

    return docRef.id;
  }

  /// Stream email dispatch history for a school
  Stream<List<OnboardingEmailRecord>> watchEmailHistory(String schoolId) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('parentOnboardingEmails')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => OnboardingEmailRecord.fromFirestore(doc))
            .toList());
  }

  /// Get a single email dispatch record
  Future<OnboardingEmailRecord?> getEmailRecord(
    String schoolId,
    String emailId,
  ) async {
    final doc = await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('parentOnboardingEmails')
        .doc(emailId)
        .get();

    if (!doc.exists) return null;
    return OnboardingEmailRecord.fromFirestore(doc);
  }
}
