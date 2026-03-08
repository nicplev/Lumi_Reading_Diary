import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/models/school_model.dart';
import 'package:lumi_reading_tracker/screens/onboarding/school_registration_wizard.dart';
import 'package:lumi_reading_tracker/services/onboarding_service.dart';

class _FakeOnboardingService extends OnboardingService {
  _FakeOnboardingService()
      : super(
          firestore: FakeFirebaseFirestore(),
          auth: MockFirebaseAuth(),
        );

  ReadingLevelSchema? createdSchema;
  List<String>? createdCustomLevels;
  ReadingLevelSchema? configuredSchema;
  List<String>? configuredCustomLevels;
  bool completed = false;

  @override
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
    createdSchema = levelSchema;
    createdCustomLevels = customLevels;
    return {
      'schoolId': 'school_1',
      'adminUserId': 'admin_1',
    };
  }

  @override
  Future<void> applyReadingLevelConfiguration({
    required String onboardingId,
    required ReadingLevelSchema levelSchema,
    List<String>? customLevels,
  }) async {
    configuredSchema = levelSchema;
    configuredCustomLevels = customLevels;
  }

  @override
  Future<void> completeOnboarding(String onboardingId) async {
    completed = true;
  }
}

void main() {
  Finder fieldByName(String name) {
    return find.byWidgetPredicate(
      (widget) => widget is FormBuilderTextField && widget.name == name,
      description: 'FormBuilderTextField($name)',
    );
  }

  testWidgets('persists selected custom reading schema through setup flow',
      (tester) async {
    final fakeService = _FakeOnboardingService();
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SchoolRegistrationWizard(
          onboardingId: 'onboarding_1',
          onboardingService: fakeService,
        ),
      ),
    );

    await tester.enterText(fieldByName('schoolName'), 'Lumi School');
    await tester.enterText(fieldByName('contactEmail'), 'office@school.test');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    await tester.enterText(fieldByName('adminFullName'), 'Admin User');
    await tester.enterText(
      fieldByName('adminEmail'),
      'admin@school.test',
    );
    await tester.enterText(
      fieldByName('adminPassword'),
      'StrongPass123',
    );
    await tester.enterText(
      fieldByName('adminPasswordConfirm'),
      'StrongPass123',
    );
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    await tester.ensureVisible(find.text('Custom'));
    await tester.tap(find.text('Custom'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    await tester.ensureVisible(fieldByName('customLevels'));
    await tester.enterText(
      fieldByName('customLevels'),
      'Blue, Green, Orange',
    );
    await tester.tap(find.text('Complete Setup'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(fakeService.createdSchema, ReadingLevelSchema.custom);
    expect(
      fakeService.createdCustomLevels,
      equals(const ['Blue', 'Green', 'Orange']),
    );
    expect(fakeService.configuredSchema, ReadingLevelSchema.custom);
    expect(
      fakeService.configuredCustomLevels,
      equals(const ['Blue', 'Green', 'Orange']),
    );
    expect(fakeService.completed, isTrue);
    expect(find.text('Welcome to Lumi!'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
