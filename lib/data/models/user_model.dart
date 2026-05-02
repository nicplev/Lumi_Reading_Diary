import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole {
  parent,
  teacher,
  schoolAdmin,
}

class UserModel {
  final String id;
  final String email;
  final String fullName;
  final UserRole role;
  final String? schoolId;
  final List<String> linkedChildren; // For parents
  final List<String> classIds; // For teachers
  final String? profileImageUrl;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastLoginAt;
  final Map<String, dynamic>? preferences;
  final String? fcmToken; // For notifications
  final String? phoneNumber; // E.164 format; populated when SMS MFA is enrolled
  final bool phoneVerified;

  UserModel({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.schoolId,
    this.linkedChildren = const [],
    this.classIds = const [],
    this.profileImageUrl,
    this.isActive = true,
    required this.createdAt,
    this.lastLoginAt,
    this.preferences,
    this.fcmToken,
    this.phoneNumber,
    this.phoneVerified = false,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      id: doc.id,
      email: data['email'] ?? '',
      fullName: data['fullName'] ?? '',
      role: UserRole.values.firstWhere(
        (e) => e.toString() == 'UserRole.${data['role']}',
        orElse: () => UserRole.parent,
      ),
      schoolId: data['schoolId'],
      linkedChildren: List<String>.from(data['linkedChildren'] ?? []),
      classIds: List<String>.from(data['classIds'] ?? []),
      profileImageUrl: data['profileImageUrl'],
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
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastLoginAt': lastLoginAt != null ? Timestamp.fromDate(lastLoginAt!) : null,
      'preferences': preferences,
      'fcmToken': fcmToken,
      'phoneNumber': phoneNumber,
      'phoneVerified': phoneVerified,
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
    bool? isActive,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    Map<String, dynamic>? preferences,
    String? fcmToken,
    String? phoneNumber,
    bool? phoneVerified,
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
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      preferences: preferences ?? this.preferences,
      fcmToken: fcmToken ?? this.fcmToken,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      phoneVerified: phoneVerified ?? this.phoneVerified,
    );
  }
}