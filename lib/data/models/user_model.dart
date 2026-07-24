import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole {
  parent,
  teacher,
  schoolAdmin,
}

class UserModel {
  final String id;
  // Nullable: parents can register with a phone number only (no email).
  // Use [contactIdentifier] for display surfaces that need a non-null label.
  final String? email;
  final String fullName;
  final UserRole role;
  final String? schoolId;
  final List<String> linkedChildren; // For parents
  final List<String> classIds; // For teachers
  final String? profileImageUrl;
  // Chosen staff Lumi character id (la_/mt_/ft_ prefixed); see StaffLumiCharacters.
  final String? characterId;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastLoginAt;
  final Map<String, dynamic>? preferences;

  /// Per-child quick-log preferences for THIS guardian
  /// (`preferences.quickLog.{studentId}`), so separated households keep
  /// independent routines (plan §6.4). Returns null when never set.
  Map<String, dynamic>? quickLogPrefsFor(String studentId) {
    final quickLog = preferences?['quickLog'];
    if (quickLog is! Map) return null;
    final child = quickLog[studentId];
    return child is Map ? Map<String, dynamic>.from(child) : null;
  }

  /// This guardian's usual quick-log minutes for [studentId], or null to
  /// fall back to the allocation target.
  int? usualMinutesFor(String studentId) {
    final value = quickLogPrefsFor(studentId)?['usualMinutes'];
    return value is num ? value.toInt() : null;
  }

  /// This guardian's pinned current book for [studentId] — lets a family
  /// quick-log a library book/comic/re-read independent of school
  /// allocation. Null when nothing is pinned.
  String? pinnedBookTitleFor(String studentId) {
    final value = quickLogPrefsFor(studentId)?['pinnedBookTitle'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }
  final String? fcmToken; // For notifications
  final String? phoneNumber; // E.164 format; populated when SMS MFA is enrolled
  final bool phoneVerified;
  final bool mfaEnabled;
  // For parents: relationship to the child (e.g. Mum, Dad, Grandparent,
  // Guardian, or a free-text value). Used for reading-log attribution and
  // co-parent visibility. Null for legacy parents and non-parent users.
  final String? relationshipLabel;
  final bool termsAccepted;
  final DateTime? termsAcceptedAt;
  final String? termsAcceptedVersion;
  final String? termsAcceptedPlatform;

  UserModel({
    required this.id,
    this.email,
    required this.fullName,
    required this.role,
    this.schoolId,
    this.linkedChildren = const [],
    this.classIds = const [],
    this.profileImageUrl,
    this.characterId,
    this.isActive = true,
    required this.createdAt,
    this.lastLoginAt,
    this.preferences,
    this.fcmToken,
    this.phoneNumber,
    this.phoneVerified = false,
    this.mfaEnabled = false,
    this.relationshipLabel,
    this.termsAccepted = false,
    this.termsAcceptedAt,
    this.termsAcceptedVersion,
    this.termsAcceptedPlatform,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      id: doc.id,
      email: data['email'] as String?,
      fullName: data['fullName'] ?? '',
      role: UserRole.values.firstWhere(
        (e) => e.toString() == 'UserRole.${data['role']}',
        orElse: () => UserRole.parent,
      ),
      schoolId: data['schoolId'],
      linkedChildren: List<String>.from(data['linkedChildren'] ?? []),
      classIds: List<String>.from(data['classIds'] ?? []),
      profileImageUrl: data['profileImageUrl'],
      characterId: data['characterId'] as String?,
      isActive: data['isActive'] ?? true,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      lastLoginAt: data['lastLoginAt'] != null
          ? (data['lastLoginAt'] as Timestamp).toDate()
          : null,
      preferences: data['preferences'],
      fcmToken: data['fcmToken'],
      phoneNumber: data['phoneNumber'],
      phoneVerified: data['phoneVerified'] ?? false,
      mfaEnabled: data['mfaEnabled'] ?? false,
      relationshipLabel: data['relationshipLabel'],
      termsAccepted: data['termsAccepted'] ?? false,
      termsAcceptedAt: data['termsAcceptedAt'] != null
          ? (data['termsAcceptedAt'] as Timestamp).toDate()
          : null,
      termsAcceptedVersion: data['termsAcceptedVersion'],
      termsAcceptedPlatform: data['termsAcceptedPlatform'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'fullName': fullName,
      'role': role.toString().split('.').last,
      'schoolId': schoolId,
      'linkedChildren': linkedChildren,
      'classIds': classIds,
      'profileImageUrl': profileImageUrl,
      'characterId': characterId,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastLoginAt':
          lastLoginAt != null ? Timestamp.fromDate(lastLoginAt!) : null,
      'preferences': preferences,
      'fcmToken': fcmToken,
      'phoneNumber': phoneNumber,
      'phoneVerified': phoneVerified,
      'mfaEnabled': mfaEnabled,
      'relationshipLabel': relationshipLabel,
      'termsAccepted': termsAccepted,
      'termsAcceptedAt':
          termsAcceptedAt != null ? Timestamp.fromDate(termsAcceptedAt!) : null,
      'termsAcceptedVersion': termsAcceptedVersion,
      'termsAcceptedPlatform': termsAcceptedPlatform,
    };
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? fullName,
    UserRole? role,
    String? schoolId,
    List<String>? linkedChildren,
    List<String>? classIds,
    String? profileImageUrl,
    String? characterId,
    bool? isActive,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    Map<String, dynamic>? preferences,
    String? fcmToken,
    String? phoneNumber,
    bool? phoneVerified,
    bool? mfaEnabled,
    String? relationshipLabel,
    bool? termsAccepted,
    DateTime? termsAcceptedAt,
    String? termsAcceptedVersion,
    String? termsAcceptedPlatform,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      schoolId: schoolId ?? this.schoolId,
      linkedChildren: linkedChildren ?? this.linkedChildren,
      classIds: classIds ?? this.classIds,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      characterId: characterId ?? this.characterId,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      preferences: preferences ?? this.preferences,
      fcmToken: fcmToken ?? this.fcmToken,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      phoneVerified: phoneVerified ?? this.phoneVerified,
      mfaEnabled: mfaEnabled ?? this.mfaEnabled,
      relationshipLabel: relationshipLabel ?? this.relationshipLabel,
      termsAccepted: termsAccepted ?? this.termsAccepted,
      termsAcceptedAt: termsAcceptedAt ?? this.termsAcceptedAt,
      termsAcceptedVersion: termsAcceptedVersion ?? this.termsAcceptedVersion,
      termsAcceptedPlatform:
          termsAcceptedPlatform ?? this.termsAcceptedPlatform,
    );
  }

  bool hasAcceptedTermsVersion(String version) =>
      termsAccepted &&
      termsAcceptedAt != null &&
      termsAcceptedVersion == version;

  /// Display-safe identifier — prefers the email, then the phone number, then
  /// a placeholder. Use this in profile / picker / impersonation surfaces so
  /// phone-only parents don't render an empty cell.
  String get contactIdentifier =>
      (email?.isNotEmpty == true ? email : null) ?? phoneNumber ?? '—';
}

/// Canonical relationship-label options shown in pickers. Stored on the
/// parent's UserModel as a plain string so future values stay forward-safe.
class GuardianRelationship {
  static const String mum = 'Mum';
  static const String dad = 'Dad';
  static const String grandparent = 'Grandparent';
  static const String guardian = 'Guardian';
  static const String other = 'Other';

  /// Preset choices offered in the chip selector (excludes free-text "Other").
  static const List<String> presets = [mum, dad, grandparent, guardian];
}
