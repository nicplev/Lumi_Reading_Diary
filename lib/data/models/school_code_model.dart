import 'package:cloud_firestore/cloud_firestore.dart';

/// Model for school registration codes used by teachers during signup.
///
/// School admins create these codes and share them with teachers who want to
/// join their school. Each code can be set to expire and can be deactivated.
class SchoolCodeModel {
  final String id;
  final String code;
  final String schoolId;
  final String schoolName;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final String? createdBy;
  final int? usageCount;
  final int? maxUsages;

  SchoolCodeModel({
    required this.id,
    required this.code,
    required this.schoolId,
    required this.schoolName,
    required this.isActive,
    required this.createdAt,
    this.expiresAt,
    this.createdBy,
    this.usageCount,
    this.maxUsages,
  });

  /// Creates a SchoolCodeModel from Firestore document
  factory SchoolCodeModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return SchoolCodeModel(
      id: doc.id,
      code: data['code'] as String,
      schoolId: data['schoolId'] as String,
      schoolName: data['schoolName'] as String,
      isActive: data['isActive'] as bool? ?? true,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      expiresAt: data['expiresAt'] != null
          ? (data['expiresAt'] as Timestamp).toDate()
          : null,
      createdBy: data['createdBy'] as String?,
      usageCount: data['usageCount'] as int? ?? 0,
      maxUsages: data['maxUsages'] as int?,
    );
  }

  /// Converts SchoolCodeModel to Firestore document format
  Map<String, dynamic> toFirestore() {
    return {
      'code': code,
      'schoolId': schoolId,
      'schoolName': schoolName,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
      'createdBy': createdBy,
      'usageCount': usageCount ?? 0,
      'maxUsages': maxUsages,
    };
  }

  /// Checks if the code is currently valid (active and not expired)
  bool get isValid {
    if (!isActive) return false;
    if (expiresAt != null && DateTime.now().isAfter(expiresAt!)) return false;
    if (maxUsages != null && (usageCount ?? 0) >= maxUsages!) return false;
    return true;
  }

  /// Gets the reason why a code is invalid (for error messages)
  String? get invalidReason {
    if (!isActive) return 'This school code has been deactivated';
    if (expiresAt != null && DateTime.now().isAfter(expiresAt!)) {
      return 'This school code has expired';
    }
    if (maxUsages != null && (usageCount ?? 0) >= maxUsages!) {
      return 'This school code has reached its maximum usage limit';
    }
    return null;
  }

  @override
  String toString() {
    return 'SchoolCodeModel(id: $id, code: $code, schoolId: $schoolId, '
        'schoolName: $schoolName, isActive: $isActive, isValid: $isValid)';
  }
}
