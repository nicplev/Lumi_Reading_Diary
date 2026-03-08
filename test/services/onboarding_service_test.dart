import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/models/school_model.dart';
import 'package:lumi_reading_tracker/services/onboarding_service.dart';

void main() {
  group('OnboardingService', () {
    test('persists selected schema and onboarding transitions', () async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth();
      final service = OnboardingService(
        firestore: firestore,
        auth: auth,
      );

      const onboardingId = 'onboarding_1';
      await firestore.collection('schoolOnboarding').doc(onboardingId).set({
        'schoolName': 'Lumi School',
        'contactEmail': 'admin@school.test',
        'status': 'demo',
        'currentStep': 'schoolInfo',
        'completedSteps': <String>[],
        'createdAt': Timestamp.now(),
      });

      final created = await service.createSchoolAndAdmin(
        onboardingId: onboardingId,
        schoolName: 'Lumi School',
        adminEmail: 'admin@school.test',
        adminPassword: 'StrongPass123',
        adminFullName: 'Admin User',
        levelSchema: ReadingLevelSchema.pmBenchmark,
      );

      await service.applyReadingLevelConfiguration(
        onboardingId: onboardingId,
        levelSchema: ReadingLevelSchema.custom,
        customLevels: const ['Blue', 'Green', 'Orange'],
      );

      await service.completeOnboarding(onboardingId);

      final schoolDoc =
          await firestore.collection('schools').doc(created['schoolId']).get();
      expect(schoolDoc.exists, isTrue);
      expect(schoolDoc.data()!['levelSchema'], equals('custom'));
      expect(
        List<String>.from(schoolDoc.data()!['customLevels'] as List<dynamic>),
        equals(const ['Blue', 'Green', 'Orange']),
      );

      final onboardingDoc = await firestore
          .collection('schoolOnboarding')
          .doc(onboardingId)
          .get();
      expect(onboardingDoc.data()!['status'], equals('active'));
      expect(onboardingDoc.data()!['currentStep'], equals('completed'));
      expect(
        List<String>.from(
            onboardingDoc.data()!['completedSteps'] as List<dynamic>),
        containsAll(
          const [
            'schoolInfo',
            'adminAccount',
            'readingLevels',
            'completed',
          ],
        ),
      );
    });
  });
}
