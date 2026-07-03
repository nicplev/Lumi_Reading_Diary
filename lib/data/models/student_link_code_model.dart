import 'package:cloud_firestore/cloud_firestore.dart';

enum LinkCodeStatus {
  active,
  used,
  expired,
  revoked,
}

/// Who a link code is meant for. Used to scope the one-active-code-per-channel
/// supersede policy so a staff-issued code and a guardian's co-parent invite
/// can be active at the same time without clobbering each other.
class LinkCodeIntent {
  static const String staffIssued = 'staff_issued';
  static const String coParentInvite = 'co_parent_invite';
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
  // Discriminator: LinkCodeIntent.staffIssued or LinkCodeIntent.coParentInvite.
  // Legacy docs without this field default to staffIssued.
  final String intendedFor;
  // Optional free-text note describing the intended recipient (e.g. "For Dad").
  final String? note;

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
    this.intendedFor = LinkCodeIntent.staffIssued,
    this.note,
  });

  factory StudentLinkCodeModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final resolvedCreatedAt =
        _readDateTime(data['createdAt']) ?? DateTime.now();
    final resolvedExpiresAt =
        _readDateTime(data['expiresAt'] ?? data['expiryDate']) ??
            resolvedCreatedAt.add(const Duration(days: 365));

    return StudentLinkCodeModel(
      id: doc.id,
      studentId: data['studentId'] ?? '',
      schoolId: data['schoolId'] ?? '',
      code: data['code'] ?? '',
      status: LinkCodeStatus.values.firstWhere(
        (e) => e.toString() == 'LinkCodeStatus.${data['status']}',
        orElse: () => LinkCodeStatus.active,
      ),
      createdAt: resolvedCreatedAt,
      expiresAt: resolvedExpiresAt,
      createdBy: data['createdBy'] ?? '',
      usedBy: data['usedBy'],
      usedAt: _readDateTime(data['usedAt']),
      revokedBy: data['revokedBy'],
      revokedAt: _readDateTime(data['revokedAt']),
      revokeReason: data['revokeReason'],
      metadata: data['metadata'],
      intendedFor: data['intendedFor'] ?? LinkCodeIntent.staffIssued,
      note: data['note'],
    );
  }

  /// Builds a model from the `verifyStudentLinkCode` callable's response
  /// payload (a plain map, not a Firestore document). The callable only returns
  /// codes that already passed the active/not-expired validation, so `status`
  /// is [LinkCodeStatus.active]. Fields the confirmation UI doesn't need
  /// (createdBy, intendedFor, …) fall back to defaults.
  factory StudentLinkCodeModel.fromVerifyPayload(Map<String, dynamic> data) {
    final rawExpires = data['expiresAt'];
    final resolvedExpiresAt = rawExpires is String
        ? (DateTime.tryParse(rawExpires) ??
            DateTime.now().add(const Duration(days: 365)))
        : DateTime.now().add(const Duration(days: 365));
    final rawMetadata = data['metadata'];
    return StudentLinkCodeModel(
      id: (data['id'] as String?) ?? '',
      studentId: (data['studentId'] as String?) ?? '',
      schoolId: (data['schoolId'] as String?) ?? '',
      code: (data['code'] as String?) ?? '',
      status: LinkCodeStatus.active,
      createdAt: DateTime.now(),
      expiresAt: resolvedExpiresAt,
      createdBy: '',
      metadata: rawMetadata is Map
          ? rawMetadata.map((k, v) => MapEntry(k.toString(), v))
          : null,
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
      'intendedFor': intendedFor,
      'note': note,
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
    String? intendedFor,
    String? note,
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
      intendedFor: intendedFor ?? this.intendedFor,
      note: note ?? this.note,
    );
  }

  bool get isCoParentInvite => intendedFor == LinkCodeIntent.coParentInvite;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isUsable => status == LinkCodeStatus.active && !isExpired;

  static DateTime? _readDateTime(
    dynamic value, {
    DateTime? fallback,
  }) {
    if (value == null) return fallback;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value) ?? fallback;
    }
    return fallback;
  }
}
