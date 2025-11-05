import 'package:cloud_firestore/cloud_firestore.dart';

enum OnboardingStatus {
  demo,
  interested,
  registered,
  setupInProgress,
  active,
  suspended,
}

enum OnboardingStep {
  schoolInfo,
  adminAccount,
  readingLevels,
  importData,
  inviteTeachers,
  completed,
}

class SchoolOnboardingModel {
  final String id;
  final String schoolName;
  final String contactEmail;
  final String? contactPhone;
  final String? contactPerson;
  final OnboardingStatus status;
  final OnboardingStep currentStep;
  final List<OnboardingStep> completedSteps;
  final DateTime createdAt;
  final DateTime? lastUpdatedAt;
  final String? schoolId; // Set when school is created
  final String? adminUserId; // Set when admin account is created
  final Map<String, dynamic>? metadata; // Store demo requests, notes, etc.
  final DateTime? demoScheduledAt;
  final DateTime? registrationCompletedAt;
  final String? referralSource;
  final int estimatedStudentCount;
  final int estimatedTeacherCount;

  SchoolOnboardingModel({
    required this.id,
    required this.schoolName,
    required this.contactEmail,
    this.contactPhone,
    this.contactPerson,
    required this.status,
    required this.currentStep,
    this.completedSteps = const [],
    required this.createdAt,
    this.lastUpdatedAt,
    this.schoolId,
    this.adminUserId,
    this.metadata,
    this.demoScheduledAt,
    this.registrationCompletedAt,
    this.referralSource,
    this.estimatedStudentCount = 0,
    this.estimatedTeacherCount = 0,
  });

  factory SchoolOnboardingModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SchoolOnboardingModel(
      id: doc.id,
      schoolName: data['schoolName'] ?? '',
      contactEmail: data['contactEmail'] ?? '',
      contactPhone: data['contactPhone'],
      contactPerson: data['contactPerson'],
      status: OnboardingStatus.values.firstWhere(
        (e) => e.toString() == 'OnboardingStatus.${data['status']}',
        orElse: () => OnboardingStatus.demo,
      ),
      currentStep: OnboardingStep.values.firstWhere(
        (e) => e.toString() == 'OnboardingStep.${data['currentStep']}',
        orElse: () => OnboardingStep.schoolInfo,
      ),
      completedSteps: (data['completedSteps'] as List<dynamic>?)
              ?.map((e) => OnboardingStep.values.firstWhere(
                    (step) => step.toString() == 'OnboardingStep.$e',
                    orElse: () => OnboardingStep.schoolInfo,
                  ))
              .toList() ??
          [],
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      lastUpdatedAt: data['lastUpdatedAt'] != null
          ? (data['lastUpdatedAt'] as Timestamp).toDate()
          : null,
      schoolId: data['schoolId'],
      adminUserId: data['adminUserId'],
      metadata: data['metadata'],
      demoScheduledAt: data['demoScheduledAt'] != null
          ? (data['demoScheduledAt'] as Timestamp).toDate()
          : null,
      registrationCompletedAt: data['registrationCompletedAt'] != null
          ? (data['registrationCompletedAt'] as Timestamp).toDate()
          : null,
      referralSource: data['referralSource'],
      estimatedStudentCount: data['estimatedStudentCount'] ?? 0,
      estimatedTeacherCount: data['estimatedTeacherCount'] ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'schoolName': schoolName,
      'contactEmail': contactEmail,
      'contactPhone': contactPhone,
      'contactPerson': contactPerson,
      'status': status.toString().split('.').last,
      'currentStep': currentStep.toString().split('.').last,
      'completedSteps':
          completedSteps.map((e) => e.toString().split('.').last).toList(),
      'createdAt': Timestamp.fromDate(createdAt),
      'lastUpdatedAt': lastUpdatedAt != null
          ? Timestamp.fromDate(lastUpdatedAt!)
          : FieldValue.serverTimestamp(),
      'schoolId': schoolId,
      'adminUserId': adminUserId,
      'metadata': metadata,
      'demoScheduledAt': demoScheduledAt != null
          ? Timestamp.fromDate(demoScheduledAt!)
          : null,
      'registrationCompletedAt': registrationCompletedAt != null
          ? Timestamp.fromDate(registrationCompletedAt!)
          : null,
      'referralSource': referralSource,
      'estimatedStudentCount': estimatedStudentCount,
      'estimatedTeacherCount': estimatedTeacherCount,
    };
  }

  SchoolOnboardingModel copyWith({
    String? id,
    String? schoolName,
    String? contactEmail,
    String? contactPhone,
    String? contactPerson,
    OnboardingStatus? status,
    OnboardingStep? currentStep,
    List<OnboardingStep>? completedSteps,
    DateTime? createdAt,
    DateTime? lastUpdatedAt,
    String? schoolId,
    String? adminUserId,
    Map<String, dynamic>? metadata,
    DateTime? demoScheduledAt,
    DateTime? registrationCompletedAt,
    String? referralSource,
    int? estimatedStudentCount,
    int? estimatedTeacherCount,
  }) {
    return SchoolOnboardingModel(
      id: id ?? this.id,
      schoolName: schoolName ?? this.schoolName,
      contactEmail: contactEmail ?? this.contactEmail,
      contactPhone: contactPhone ?? this.contactPhone,
      contactPerson: contactPerson ?? this.contactPerson,
      status: status ?? this.status,
      currentStep: currentStep ?? this.currentStep,
      completedSteps: completedSteps ?? this.completedSteps,
      createdAt: createdAt ?? this.createdAt,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      schoolId: schoolId ?? this.schoolId,
      adminUserId: adminUserId ?? this.adminUserId,
      metadata: metadata ?? this.metadata,
      demoScheduledAt: demoScheduledAt ?? this.demoScheduledAt,
      registrationCompletedAt:
          registrationCompletedAt ?? this.registrationCompletedAt,
      referralSource: referralSource ?? this.referralSource,
      estimatedStudentCount:
          estimatedStudentCount ?? this.estimatedStudentCount,
      estimatedTeacherCount:
          estimatedTeacherCount ?? this.estimatedTeacherCount,
    );
  }

  double get progressPercentage {
    final totalSteps = OnboardingStep.values.length;
    return (completedSteps.length / totalSteps) * 100;
  }
}
