import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/services/assert_writable.dart';
import '../core/services/functions_instance.dart';
import '../data/models/school_onboarding_model.dart';
import '../data/models/school_model.dart';
import '../data/models/user_model.dart';

typedef WritableGuard = void Function({
  required String opLabel,
  String? collection,
  String? docId,
  String? operation,
});

class OnboardingService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  OnboardingService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    Future<dynamic> Function(String name, Map<String, dynamic> data)?
        callableInvoker,
    WritableGuard writableGuard = assertWritable,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _callableInvoker = callableInvoker,
        _writableGuard = writableGuard;

  final Future<dynamic> Function(String name, Map<String, dynamic> data)?
      _callableInvoker;
  final WritableGuard _writableGuard;

  Future<dynamic> _call(String name, Map<String, dynamic> data) async {
    final invoker = _callableInvoker;
    if (invoker != null) return invoker(name, data);
    final result = await lumiFunctions.httpsCallable(name).call(data);
    return result.data;
  }

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
    _writableGuard(
      opLabel: 'onboarding.createDemoRequest',
      collection: 'schoolOnboarding',
      operation: 'create',
    );
    final notes = <String>[
      if (contactPhone?.trim().isNotEmpty == true)
        'Phone: ${contactPhone!.trim()}',
      if (referralSource?.trim().isNotEmpty == true)
        'Referral: ${referralSource!.trim()}',
      'Estimated students: $estimatedStudentCount',
      'Estimated teachers: $estimatedTeacherCount',
    ].join('\n');
    final raw = await _call('submitDemoRequest', {
      'schoolName': schoolName.trim(),
      'contactPerson': contactPerson?.trim().isNotEmpty == true
          ? contactPerson!.trim()
          : 'School enquiry',
      'contactEmail': contactEmail.trim(),
      'intent': 'demo',
      'message': notes,
      if (contactPhone?.trim().isNotEmpty == true)
        'contactPhone': contactPhone!.trim(),
      if (referralSource?.trim().isNotEmpty == true)
        'referralSource': referralSource!.trim(),
      'estimatedStudentCount': estimatedStudentCount,
      'estimatedTeacherCount': estimatedTeacherCount,
    });
    if (raw is! Map || raw['id'] is! String || (raw['id'] as String).isEmpty) {
      throw FirebaseFunctionsException(
        code: 'internal',
        message: 'Demo request did not return a valid reference.',
      );
    }
    return raw['id'] as String;
  }

  // Update onboarding status
  Future<void> updateOnboardingStatus(
    String onboardingId,
    OnboardingStatus status,
  ) async {
    _writableGuard(
      opLabel: 'onboarding.updateOnboardingStatus',
      collection: 'schoolOnboarding',
      docId: onboardingId,
      operation: 'update',
    );
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
    _writableGuard(
      opLabel: 'onboarding.completeStep',
      collection: 'schoolOnboarding',
      docId: onboardingId,
      operation: 'update',
    );
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

  Future<void> _appendCompletedSteps(
    String onboardingId,
    List<OnboardingStep> steps, {
    OnboardingStep? currentStep,
  }) async {
    final doc =
        await _firestore.collection('schoolOnboarding').doc(onboardingId).get();
    if (!doc.exists) return;

    final onboarding = SchoolOnboardingModel.fromFirestore(doc);
    final updatedSteps = List<OnboardingStep>.from(onboarding.completedSteps);
    for (final step in steps) {
      if (!updatedSteps.contains(step)) {
        updatedSteps.add(step);
      }
    }

    await _firestore.collection('schoolOnboarding').doc(onboardingId).update({
      'completedSteps':
          updatedSteps.map((e) => e.toString().split('.').last).toList(),
      if (currentStep != null)
        'currentStep': currentStep.toString().split('.').last,
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
    Map<String, String>? levelColors,
    String? address,
    String? contactEmail,
    String? contactPhone,
    String? logoUrl,
    String? primaryColor,
    String? secondaryColor,
  }) async {
    _writableGuard(
      opLabel: 'onboarding.createSchoolAndAdmin',
      collection: 'schools',
      operation: 'create',
    );
    UserCredential? userCredential;
    DocumentReference<Map<String, dynamic>>? schoolDoc;

    try {
      // 1. Create admin user account
      userCredential = await _auth.createUserWithEmailAndPassword(
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
        customLevels:
            levelSchema == ReadingLevelSchema.none ? null : customLevels,
        levelColors:
            levelSchema == ReadingLevelSchema.none ? null : levelColors,
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

      schoolDoc =
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
          .set({
        ...adminUser.toFirestore(),
        'permissions': {
          'notifications': {
            'assignedClasses': true,
            'assignedStudents': true,
            'schedule': true,
            'wholeSchool': true,
          },
        },
      });

      // 4. Update onboarding record
      await _firestore.collection('schoolOnboarding').doc(onboardingId).update({
        'schoolId': schoolId,
        'adminUserId': adminUserId,
        'status': OnboardingStatus.registered.toString().split('.').last,
        'currentStep': OnboardingStep.readingLevels.toString().split('.').last,
        'registeredAt': FieldValue.serverTimestamp(),
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      });

      await _appendCompletedSteps(
        onboardingId,
        [OnboardingStep.schoolInfo, OnboardingStep.adminAccount],
        currentStep: OnboardingStep.readingLevels,
      );

      await _firestore.collection('schoolOnboarding').doc(onboardingId).update({
        'status': OnboardingStatus.setupInProgress.toString().split('.').last,
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      });

      return {
        'schoolId': schoolId,
        'adminUserId': adminUserId,
      };
    } catch (e) {
      // Best effort rollback to avoid orphaned auth users during partial failures.
      if (schoolDoc == null && userCredential?.user != null) {
        try {
          await userCredential!.user!.delete();
        } catch (_) {}
      }

      await _firestore.collection('schoolOnboarding').doc(onboardingId).update({
        'status': OnboardingStatus.interested.toString().split('.').last,
        'currentStep': OnboardingStep.adminAccount.toString().split('.').last,
        'lastError': e.toString(),
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      });
      throw Exception('Failed to create school and admin: $e');
    }
  }

  Future<void> applyReadingLevelConfiguration({
    required String onboardingId,
    required ReadingLevelSchema levelSchema,
    List<String>? customLevels,
    Map<String, String>? levelColors,
  }) async {
    final doc =
        await _firestore.collection('schoolOnboarding').doc(onboardingId).get();
    if (!doc.exists) {
      throw Exception('Onboarding record not found');
    }

    final onboarding = SchoolOnboardingModel.fromFirestore(doc);
    if (onboarding.schoolId == null || onboarding.schoolId!.isEmpty) {
      throw Exception('School not created yet for onboarding');
    }

    final needsCustomLevels = levelSchema == ReadingLevelSchema.custom ||
        levelSchema == ReadingLevelSchema.namedLevels ||
        levelSchema == ReadingLevelSchema.colouredLevels;
    await _firestore.collection('schools').doc(onboarding.schoolId).update({
      'levelSchema': levelSchema.toString().split('.').last,
      'customLevels': needsCustomLevels ? (customLevels ?? []) : null,
      'levelColors':
          levelSchema == ReadingLevelSchema.colouredLevels ? levelColors : null,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _appendCompletedSteps(
      onboardingId,
      [OnboardingStep.readingLevels],
      currentStep: OnboardingStep.completed,
    );
  }

  // Complete onboarding and activate school
  Future<void> completeOnboarding(String onboardingId) async {
    await _appendCompletedSteps(
      onboardingId,
      [OnboardingStep.completed],
      currentStep: OnboardingStep.completed,
    );

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

  // NOTE: generateSchoolCode() was removed 2026-07-20. It was unreachable
  // (no callers anywhere) and superseded by the super-admin portal, which
  // mints codes in admin/src/lib/firestore/school-codes.ts: 10 characters
  // from an unambiguous alphabet (no I/O/0/1) with a uniqueness retry loop.
  //
  // It also carried a latent crash: it bounded .substring() by the ORIGINAL
  // name length while applying it to the letters-only string, so any name
  // with >=3 characters but <3 letters threw a RangeError — 'A-B' and
  // 'X 1 2' both crashed. Reproduced before removal.
}
