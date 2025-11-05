import 'package:cloud_firestore/cloud_firestore.dart';

enum LinkCodeStatus {
  active,
  used,
  expired,
  revoked,
}

class StudentLinkCodeModel {
  final String id;
  final String studentId;
  final String schoolId;
  final String code; // Unique 8-character code
  final LinkCodeStatus status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String createdBy; // User ID of teacher/admin who created it
  final String? usedBy; // Parent user ID who used it
  final DateTime? usedAt;
  final String? revokedBy;
  final DateTime? revokedAt;
  final String? revokeReason;
  final Map<String, dynamic>? metadata;

  StudentLinkCodeModel({
    required this.id,
    required this.studentId,
    required this.schoolId,
    required this.code,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    required this.createdBy,
    this.usedBy,
    this.usedAt,
    this.revokedBy,
    this.revokedAt,
    this.revokeReason,
    this.metadata,
  });

  factory StudentLinkCodeModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return StudentLinkCodeModel(
      id: doc.id,
      studentId: data['studentId'] ?? '',
      schoolId: data['schoolId'] ?? '',
      code: data['code'] ?? '',
      status: LinkCodeStatus.values.firstWhere(
        (e) => e.toString() == 'LinkCodeStatus.${data['status']}',
        orElse: () => LinkCodeStatus.active,
      ),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      expiresAt: (data['expiresAt'] as Timestamp).toDate(),
      createdBy: data['createdBy'] ?? '',
      usedBy: data['usedBy'],
      usedAt: data['usedAt'] != null
          ? (data['usedAt'] as Timestamp).toDate()
          : null,
      revokedBy: data['revokedBy'],
      revokedAt: data['revokedAt'] != null
          ? (data['revokedAt'] as Timestamp).toDate()
          : null,
      revokeReason: data['revokeReason'],
      metadata: data['metadata'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'studentId': studentId,
      'schoolId': schoolId,
      'code': code,
      'status': status.toString().split('.').last,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'createdBy': createdBy,
      'usedBy': usedBy,
      'usedAt': usedAt != null ? Timestamp.fromDate(usedAt!) : null,
      'revokedBy': revokedBy,
      'revokedAt': revokedAt != null ? Timestamp.fromDate(revokedAt!) : null,
      'revokeReason': revokeReason,
      'metadata': metadata,
    };
  }

  StudentLinkCodeModel copyWith({
    String? id,
    String? studentId,
    String? schoolId,
    String? code,
    LinkCodeStatus? status,
    DateTime? createdAt,
    DateTime? expiresAt,
    String? createdBy,
    String? usedBy,
    DateTime? usedAt,
    String? revokedBy,
    DateTime? revokedAt,
    String? revokeReason,
    Map<String, dynamic>? metadata,
  }) {
    return StudentLinkCodeModel(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      schoolId: schoolId ?? this.schoolId,
      code: code ?? this.code,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      createdBy: createdBy ?? this.createdBy,
      usedBy: usedBy ?? this.usedBy,
      usedAt: usedAt ?? this.usedAt,
      revokedBy: revokedBy ?? this.revokedBy,
      revokedAt: revokedAt ?? this.revokedAt,
      revokeReason: revokeReason ?? this.revokeReason,
      metadata: metadata ?? this.metadata,
    );
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isUsable =>
      status == LinkCodeStatus.active && !isExpired;
}
