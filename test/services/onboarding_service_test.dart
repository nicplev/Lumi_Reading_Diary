import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/models/school_model.dart';
import 'package:lumi_reading_tracker/data/models/school_onboarding_model.dart';
import 'package:lumi_reading_tracker/services/onboarding_service.dart';

void main() {
  group('OnboardingService', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;
    late OnboardingService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      auth = MockFirebaseAuth();
      service = OnboardingService(firestore: firestore, auth: auth);
    });

    Future<String> seedOnboardingDoc({
      String id = 'onboarding_1',
      String status = 'demo',
      String currentStep = 'schoolInfo',
      List<String> completedSteps = const [],
    }) async {
      await firestore.collection('schoolOnboarding').doc(id).set({
        'schoolName': 'Lumi School',
        'contactEmail': 'admin@school.test',
        'status': status,
        'currentStep': currentStep,
        'completedSteps': completedSteps,
        'createdAt': Timestamp.now(),
      });
      return id;
    }

    // ── createDemoRequest ──

    group('createDemoRequest', () {
      test('creates document with correct fields and returns id', () async {
        final id = await service.createDemoRequest(
          schoolName: 'Test School',
          contactEmail: 'test@school.com',
          contactPhone: '0412345678',
          contactPerson: 'Jane Doe',
          referralSource: 'Google',
          estimatedStudentCount: 100,
          estimatedTeacherCount: 5,
        );

        expect(id, isNotEmpty);

        final doc =
            await firestore.collection('schoolOnboarding').doc(id).get();
        expect(doc.exists, isTrue);
        expect(doc.data()!['schoolName'], 'Test School');
        expect(doc.data()!['contactEmail'], 'test@school.com');
        expect(doc.data()!['contactPhone'], '0412345678');
        expect(doc.data()!['contactPerson'], 'Jane Doe');
        expect(doc.data()!['referralSource'], 'Google');
        expect(doc.data()!['estimatedStudentCount'], 100);
        expect(doc.data()!['estimatedTeacherCount'], 5);
        expect(doc.data()!['status'], 'demo');
        expect(doc.data()!['currentStep'], 'schoolInfo');
      });

      test('creates document with only required fields', () async {
        final id = await service.createDemoRequest(
          schoolName: 'Minimal School',
          contactEmail: 'min@school.com',
        );

        final doc =
            await firestore.collection('schoolOnboarding').doc(id).get();
        expect(doc.data()!['schoolName'], 'Minimal School');
        expect(doc.data()!['estimatedStudentCount'], 0);
        expect(doc.data()!['estimatedTeacherCount'], 0);
        expect(doc.data()!['contactPhone'], isNull);
      });
    });

    // ── updateOnboardingStatus ──

    group('updateOnboardingStatus', () {
      test('updates status field on existing document', () async {
        final id = await seedOnboardingDoc();

        await service.updateOnboardingStatus(id, OnboardingStatus.interested);

        final doc =
            await firestore.collection('schoolOnboarding').doc(id).get();
        expect(doc.data()!['status'], 'interested');
      });

      test('can transition through all status values', () async {
        final id = await seedOnboardingDoc();

        for (final status in OnboardingStatus.values) {
          await service.updateOnboardingStatus(id, status);
          final doc =
              await firestore.collection('schoolOnboarding').doc(id).get();
          expect(doc.data()!['status'], status.toString().split('.').last);
        }
      });
    });

    // ── completeStep ──

    group('completeStep', () {
      test('adds step to completedSteps and advances currentStep', () async {
        final id = await seedOnboardingDoc();

        await service.completeStep(id, OnboardingStep.schoolInfo);

        final doc =
            await firestore.collection('schoolOnboarding').doc(id).get();
        final steps = List<String>.from(doc.data()!['completedSteps']);
        expect(steps, contains('schoolInfo'));
        expect(doc.data()!['currentStep'], 'adminAccount');
      });

      test('does not duplicate steps when called twice', () async {
        final id = await seedOnboardingDoc();

        await service.completeStep(id, OnboardingStep.schoolInfo);
        await service.completeStep(id, OnboardingStep.schoolInfo);

        final doc =
            await firestore.collection('schoolOnboarding').doc(id).get();
        final steps = List<String>.from(doc.data()!['completedSteps']);
        expect(steps.where((s) => s == 'schoolInfo').length, 1);
      });

      test('completing last step sets currentStep to completed', () async {
        final id = await seedOnboardingDoc(
          completedSteps: [
            'schoolInfo',
            'adminAccount',
            'readingLevels',
            'importData',
          ],
        );

        await service.completeStep(id, OnboardingStep.inviteTeachers);

        final doc =
            await firestore.collection('schoolOnboarding').doc(id).get();
        expect(doc.data()!['currentStep'], 'completed');
      });
    });

    // ── createSchoolAndAdmin ──

    group('createSchoolAndAdmin', () {
      test('creates school, admin user doc, and updates onboarding', () async {
        final id = await seedOnboardingDoc();

        final result = await service.createSchoolAndAdmin(
          onboardingId: id,
          schoolName: 'Lumi School',
          adminEmail: 'admin@school.test',
          adminPassword: 'StrongPass123',
          adminFullName: 'Admin User',
          levelSchema: ReadingLevelSchema.aToZ,
        );

        expect(result['schoolId'], isNotEmpty);
        expect(result['adminUserId'], isNotEmpty);

        // Verify school document
        final schoolDoc = await firestore
            .collection('schools')
            .doc(result['schoolId'])
            .get();
        expect(schoolDoc.exists, isTrue);
        expect(schoolDoc.data()!['name'], 'Lumi School');
        expect(schoolDoc.data()!['levelSchema'], 'aToZ');
        expect(schoolDoc.data()!['isActive'], isTrue);

        // Verify admin user document
        final adminDoc = await firestore
            .collection('schools')
            .doc(result['schoolId'])
            .collection('users')
            .doc(result['adminUserId'])
            .get();
        expect(adminDoc.exists, isTrue);
        expect(adminDoc.data()!['email'], 'admin@school.test');
        expect(adminDoc.data()!['fullName'], 'Admin User');
        expect(adminDoc.data()!['role'], 'schoolAdmin');

        // Verify onboarding status updated
        final onboardingDoc =
            await firestore.collection('schoolOnboarding').doc(id).get();
        expect(onboardingDoc.data()!['status'], 'setupInProgress');
        expect(onboardingDoc.data()!['schoolId'], result['schoolId']);
        expect(onboardingDoc.data()!['adminUserId'], result['adminUserId']);
      });

      test('stores optional address and contact info on school', () async {
        final id = await seedOnboardingDoc();

        final result = await service.createSchoolAndAdmin(
          onboardingId: id,
          schoolName: 'Full School',
          adminEmail: 'admin@full.test',
          adminPassword: 'Pass1234',
          adminFullName: 'Full Admin',
          levelSchema: ReadingLevelSchema.pmBenchmark,
          address: '123 School St',
          contactEmail: 'office@full.test',
          contactPhone: '0400000000',
        );

        final schoolDoc = await firestore
            .collection('schools')
            .doc(result['schoolId'])
            .get();
        expect(schoolDoc.data()!['address'], '123 School St');
        expect(schoolDoc.data()!['contactEmail'], 'office@full.test');
        expect(schoolDoc.data()!['contactPhone'], '0400000000');
      });

      test('uses admin email as contact when none provided', () async {
        final id = await seedOnboardingDoc();

        final result = await service.createSchoolAndAdmin(
          onboardingId: id,
          schoolName: 'School',
          adminEmail: 'admin@example.test',
          adminPassword: 'Pass1234',
          adminFullName: 'Admin',
          levelSchema: ReadingLevelSchema.aToZ,
        );

        final schoolDoc = await firestore
            .collection('schools')
            .doc(result['schoolId'])
            .get();
        expect(schoolDoc.data()!['contactEmail'], 'admin@example.test');
      });

      test('marks schoolInfo and adminAccount as completed steps', () async {
        final id = await seedOnboardingDoc();

        await service.createSchoolAndAdmin(
          onboardingId: id,
          schoolName: 'Step School',
          adminEmail: 'admin@step.test',
          adminPassword: 'Pass1234',
          adminFullName: 'Admin',
          levelSchema: ReadingLevelSchema.aToZ,
        );

        final doc =
            await firestore.collection('schoolOnboarding').doc(id).get();
        final steps = List<String>.from(doc.data()!['completedSteps']);
        expect(steps, containsAll(['schoolInfo', 'adminAccount']));
      });
    });

    // ── applyReadingLevelConfiguration ──

    group('applyReadingLevelConfiguration', () {
      test('updates school with custom reading levels', () async {
        final id = await seedOnboardingDoc();
        final result = await service.createSchoolAndAdmin(
          onboardingId: id,
          schoolName: 'Level School',
          adminEmail: 'admin@level.test',
          adminPassword: 'Pass1234',
          adminFullName: 'Admin',
          levelSchema: ReadingLevelSchema.aToZ,
        );

        await service.applyReadingLevelConfiguration(
          onboardingId: id,
          levelSchema: ReadingLevelSchema.custom,
          customLevels: ['Red', 'Blue', 'Green'],
        );

        final schoolDoc = await firestore
            .collection('schools')
            .doc(result['schoolId'])
            .get();
        expect(schoolDoc.data()!['levelSchema'], 'custom');
        expect(
          List<String>.from(schoolDoc.data()!['customLevels']),
          equals(['Red', 'Blue', 'Green']),
        );
      });

      test('clears customLevels when switching to standard schema', () async {
        final id = await seedOnboardingDoc();
        final result = await service.createSchoolAndAdmin(
          onboardingId: id,
          schoolName: 'Standard School',
          adminEmail: 'admin@std.test',
          adminPassword: 'Pass1234',
          adminFullName: 'Admin',
          levelSchema: ReadingLevelSchema.custom,
          customLevels: ['A', 'B', 'C'],
        );

        await service.applyReadingLevelConfiguration(
          onboardingId: id,
          levelSchema: ReadingLevelSchema.pmBenchmark,
        );

        final schoolDoc = await firestore
            .collection('schools')
            .doc(result['schoolId'])
            .get();
        expect(schoolDoc.data()!['levelSchema'], 'pmBenchmark');
        expect(schoolDoc.data()!['customLevels'], isNull);
      });

      test('throws when onboarding record does not exist', () async {
        await expectLater(
          () => service.applyReadingLevelConfiguration(
            onboardingId: 'nonexistent',
            levelSchema: ReadingLevelSchema.aToZ,
          ),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('not found'),
          )),
        );
      });

      test('throws when school has not been created yet', () async {
        final id = await seedOnboardingDoc();

        await expectLater(
          () => service.applyReadingLevelConfiguration(
            onboardingId: id,
            levelSchema: ReadingLevelSchema.aToZ,
          ),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('School not created'),
          )),
        );
      });

      test('marks readingLevels as completed step', () async {
        final id = await seedOnboardingDoc();
        await service.createSchoolAndAdmin(
          onboardingId: id,
          schoolName: 'Complete School',
          adminEmail: 'admin@complete.test',
          adminPassword: 'Pass1234',
          adminFullName: 'Admin',
          levelSchema: ReadingLevelSchema.aToZ,
        );

        await service.applyReadingLevelConfiguration(
          onboardingId: id,
          levelSchema: ReadingLevelSchema.aToZ,
        );

        final doc =
            await firestore.collection('schoolOnboarding').doc(id).get();
        final steps = List<String>.from(doc.data()!['completedSteps']);
        expect(steps, contains('readingLevels'));
      });
    });

    // ── completeOnboarding ──

    group('completeOnboarding', () {
      test('sets status to active and currentStep to completed', () async {
        final id = await seedOnboardingDoc();
        await service.createSchoolAndAdmin(
          onboardingId: id,
          schoolName: 'Finish School',
          adminEmail: 'admin@finish.test',
          adminPassword: 'Pass1234',
          adminFullName: 'Admin',
          levelSchema: ReadingLevelSchema.aToZ,
        );

        await service.completeOnboarding(id);

        final doc =
            await firestore.collection('schoolOnboarding').doc(id).get();
        expect(doc.data()!['status'], 'active');
        expect(doc.data()!['currentStep'], 'completed');
        expect(
          List<String>.from(doc.data()!['completedSteps']),
          contains('completed'),
        );
      });
    });

    // ── Full end-to-end flow ──

    group('full onboarding flow', () {
      test('persists selected schema and onboarding transitions', () async {
        final id = await seedOnboardingDoc();

        final created = await service.createSchoolAndAdmin(
          onboardingId: id,
          schoolName: 'Lumi School',
          adminEmail: 'admin@school.test',
          adminPassword: 'StrongPass123',
          adminFullName: 'Admin User',
          levelSchema: ReadingLevelSchema.pmBenchmark,
        );

        await service.applyReadingLevelConfiguration(
          onboardingId: id,
          levelSchema: ReadingLevelSchema.custom,
          customLevels: const ['Blue', 'Green', 'Orange'],
        );

        await service.completeOnboarding(id);

        final schoolDoc = await firestore
            .collection('schools')
            .doc(created['schoolId'])
            .get();
        expect(schoolDoc.exists, isTrue);
        expect(schoolDoc.data()!['levelSchema'], equals('custom'));
        expect(
          List<String>.from(schoolDoc.data()!['customLevels'] as List<dynamic>),
          equals(const ['Blue', 'Green', 'Orange']),
        );

        final onboardingDoc =
            await firestore.collection('schoolOnboarding').doc(id).get();
        expect(onboardingDoc.data()!['status'], equals('active'));
        expect(onboardingDoc.data()!['currentStep'], equals('completed'));
        expect(
          List<String>.from(
              onboardingDoc.data()!['completedSteps'] as List<dynamic>),
          containsAll(const [
            'schoolInfo',
            'adminAccount',
            'readingLevels',
            'completed',
          ]),
        );
      });

      test('demo request -> school creation -> config -> activation', () async {
        // Step 1: Demo request
        final demoId = await service.createDemoRequest(
          schoolName: 'New School',
          contactEmail: 'contact@new.school',
          contactPerson: 'Principal Smith',
          estimatedStudentCount: 200,
          estimatedTeacherCount: 10,
        );

        var doc =
            await firestore.collection('schoolOnboarding').doc(demoId).get();
        expect(doc.data()!['status'], 'demo');

        // Step 2: Schedule demo
        final demoDate = DateTime(2026, 4, 1);
        await service.scheduleDemo(demoId, demoDate);

        doc =
            await firestore.collection('schoolOnboarding').doc(demoId).get();
        expect(doc.data()!['status'], 'interested');

        // Step 3: Create school and admin
        final result = await service.createSchoolAndAdmin(
          onboardingId: demoId,
          schoolName: 'New School',
          adminEmail: 'admin@new.school',
          adminPassword: 'SecurePass1',
          adminFullName: 'Principal Smith',
          levelSchema: ReadingLevelSchema.aToZ,
        );

        doc =
            await firestore.collection('schoolOnboarding').doc(demoId).get();
        expect(doc.data()!['status'], 'setupInProgress');
        expect(doc.data()!['schoolId'], result['schoolId']);

        // Step 4: Configure reading levels
        await service.applyReadingLevelConfiguration(
          onboardingId: demoId,
          levelSchema: ReadingLevelSchema.pmBenchmark,
        );

        // Step 5: Complete onboarding
        await service.completeOnboarding(demoId);

        doc =
            await firestore.collection('schoolOnboarding').doc(demoId).get();
        expect(doc.data()!['status'], 'active');
        expect(doc.data()!['currentStep'], 'completed');
      });
    });

    // ── getOnboarding / getOnboardingByEmail ──

    group('getOnboarding', () {
      test('returns model for existing id', () async {
        final id = await seedOnboardingDoc();
        final result = await service.getOnboarding(id);
        expect(result, isNotNull);
        expect(result!.schoolName, 'Lumi School');
      });

      test('returns null for nonexistent id', () async {
        final result = await service.getOnboarding('nonexistent');
        expect(result, isNull);
      });
    });

    group('getOnboardingByEmail', () {
      test('finds record by contact email', () async {
        await seedOnboardingDoc();
        final result =
            await service.getOnboardingByEmail('admin@school.test');
        expect(result, isNotNull);
        expect(result!.contactEmail, 'admin@school.test');
      });

      test('returns null when email not found', () async {
        final result =
            await service.getOnboardingByEmail('unknown@test.com');
        expect(result, isNull);
      });
    });

    // ── scheduleDemo ──

    group('scheduleDemo', () {
      test('sets demo date and transitions to interested', () async {
        final id = await seedOnboardingDoc();
        final demoDate = DateTime(2026, 5, 1, 10, 0);

        await service.scheduleDemo(id, demoDate);

        final doc =
            await firestore.collection('schoolOnboarding').doc(id).get();
        expect(doc.data()!['status'], 'interested');
        expect(doc.data()!['demoScheduledAt'], isNotNull);
      });
    });

    // ── generateSchoolCode ──

    group('generateSchoolCode', () {
      test('generates code from school name prefix + 4 digits', () async {
        final code = service.generateSchoolCode('Sunshine Primary');
        expect(code, hasLength(7)); // 3 letters + 4 digits
        expect(code.substring(0, 3), 'SUN');
        expect(int.tryParse(code.substring(3)), isNotNull);
      });

      test('handles short school names', () async {
        final code = service.generateSchoolCode('AB');
        expect(code.length, greaterThanOrEqualTo(5)); // 1-2 letters + 4 digits
      });

      test('strips non-alpha characters from name', () async {
        final code = service.generateSchoolCode('St. Mary\'s');
        expect(code.substring(0, 3), 'STM');
      });
    });
  });
}
