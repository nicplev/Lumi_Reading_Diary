import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/models/school_onboarding_model.dart';
import '../data/models/school_model.dart';
import '../data/models/user_model.dart';

class OnboardingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Create a demo request
  Future<String> createDemoRequest({
    required String schoolName,
    required String contactEmail,
    String? contactPhone,
    String? contactPerson,
    String? referralSource,
    int estimatedStudentCount = 0,
    int estimatedTeacherCount = 0,
  }) async {
    final onboarding = SchoolOnboardingModel(
      id: '',
      schoolName: schoolName,
      contactEmail: contactEmail,
      contactPhone: contactPhone,
      contactPerson: contactPerson,
      status: OnboardingStatus.demo,
      currentStep: OnboardingStep.schoolInfo,
      createdAt: DateTime.now(),
      referralSource: referralSource,
      estimatedStudentCount: estimatedStudentCount,
      estimatedTeacherCount: estimatedTeacherCount,
    );

    final docRef = await _firestore
        .collection('schoolOnboarding')
        .add(onboarding.toFirestore());

    return docRef.id;
  }

  // Update onboarding status
  Future<void> updateOnboardingStatus(
    String onboardingId,
    OnboardingStatus status,
  ) async {
    await _firestore.collection('schoolOnboarding').doc(onboardingId).update({
      'status': status.toString().split('.').last,
      'lastUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Complete an onboarding step
  Future<void> completeStep(
    String onboardingId,
    OnboardingStep step,
  ) async {
    final doc =
        await _firestore.collection('schoolOnboarding').doc(onboardingId).get();
    final onboarding = SchoolOnboardingModel.fromFirestore(doc);

    final updatedSteps = List<OnboardingStep>.from(onboarding.completedSteps);
    if (!updatedSteps.contains(step)) {
      updatedSteps.add(step);
    }

    // Determine next step
    final currentIndex = OnboardingStep.values.indexOf(step);
    final nextStep = currentIndex < OnboardingStep.values.length - 1
        ? OnboardingStep.values[currentIndex + 1]
        : OnboardingStep.completed;

    await _firestore.collection('schoolOnboarding').doc(onboardingId).update({
      'completedSteps':
          updatedSteps.map((e) => e.toString().split('.').last).toList(),
      'currentStep': nextStep.toString().split('.').last,
      'lastUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Create school and admin account during onboarding
  Future<Map<String, String>> createSchoolAndAdmin({
    required String onboardingId,
    required String schoolName,
    required String adminEmail,
    required String adminPassword,
    required String adminFullName,
    required ReadingLevelSchema levelSchema,
    List<String>? customLevels,
    String? address,
    String? contactEmail,
    String? contactPhone,
    String? logoUrl,
    String? primaryColor,
    String? secondaryColor,
  }) async {
    try {
      // 1. Create admin user account
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: adminEmail,
        password: adminPassword,
      );

      final adminUserId = userCredential.user!.uid;

      // 2. Create school document
      final school = SchoolModel(
        id: '',
        name: schoolName,
        logoUrl: logoUrl,
        primaryColor: primaryColor,
        secondaryColor: secondaryColor,
        levelSchema: levelSchema,
        customLevels: customLevels,
        termDates: {},
        quietHours: {'start': '19:00', 'end': '07:00'},
        timezone: 'UTC',
        address: address,
        contactEmail: contactEmail ?? adminEmail,
        contactPhone: contactPhone,
        createdAt: DateTime.now(),
        createdBy: adminUserId,
        isActive: true,
      );

      final schoolDoc =
          await _firestore.collection('schools').add(school.toFirestore());
      final schoolId = schoolDoc.id;

      // 3. Create admin user document in the school
      final adminUser = UserModel(
        id: adminUserId,
        email: adminEmail,
        fullName: adminFullName,
        role: UserRole.schoolAdmin,
        schoolId: schoolId,
        createdAt: DateTime.now(),
        isActive: true,
      );

      await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('users')
          .doc(adminUserId)
          .set(adminUser.toFirestore());

      // 4. Update onboarding record
      await _firestore.collection('schoolOnboarding').doc(onboardingId).update({
        'schoolId': schoolId,
        'adminUserId': adminUserId,
        'status': OnboardingStatus.setupInProgress.toString().split('.').last,
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      });

      // 5. Complete the admin account step
      await completeStep(onboardingId, OnboardingStep.adminAccount);

      return {
        'schoolId': schoolId,
        'adminUserId': adminUserId,
      };
    } catch (e) {
      throw Exception('Failed to create school and admin: $e');
    }
  }

  // Complete onboarding and activate school
  Future<void> completeOnboarding(String onboardingId) async {
    await _firestore.collection('schoolOnboarding').doc(onboardingId).update({
      'status': OnboardingStatus.active.toString().split('.').last,
      'currentStep': OnboardingStep.completed.toString().split('.').last,
      'registrationCompletedAt': FieldValue.serverTimestamp(),
      'lastUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Get onboarding by ID
  Future<SchoolOnboardingModel?> getOnboarding(String onboardingId) async {
    final doc =
        await _firestore.collection('schoolOnboarding').doc(onboardingId).get();
    if (doc.exists) {
      return SchoolOnboardingModel.fromFirestore(doc);
    }
    return null;
  }

  // Get onboarding by email
  Future<SchoolOnboardingModel?> getOnboardingByEmail(String email) async {
    final query = await _firestore
        .collection('schoolOnboarding')
        .where('contactEmail', isEqualTo: email)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      return SchoolOnboardingModel.fromFirestore(query.docs.first);
    }
    return null;
  }

  // Schedule demo
  Future<void> scheduleDemo(String onboardingId, DateTime demoDate) async {
    await _firestore.collection('schoolOnboarding').doc(onboardingId).update({
      'demoScheduledAt': Timestamp.fromDate(demoDate),
      'status': OnboardingStatus.interested.toString().split('.').last,
      'lastUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Get all onboarding requests (for admin dashboard)
  Stream<List<SchoolOnboardingModel>> getOnboardingRequests() {
    return _firestore
        .collection('schoolOnboarding')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => SchoolOnboardingModel.fromFirestore(doc))
            .toList());
  }

  // Generate unique school code for easy identification
  String generateSchoolCode(String schoolName) {
    final cleanName = schoolName
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z]'), '')
        .substring(0, min(3, schoolName.length));
    final random = Random().nextInt(9999).toString().padLeft(4, '0');
    return '$cleanName$random';
  }
}
