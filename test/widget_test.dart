import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/providers/user_provider.dart';
import 'package:lumi_reading_tracker/main.dart';
import 'package:lumi_reading_tracker/services/firebase_service.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';

import 'helpers/firebase_mock.dart';
import 'helpers/mock_firebase_service.dart';

void main() {
  final mockAuth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(
      isAnonymous: false,
      uid: 'some_uid',
      email: 'test@example.com',
      displayName: 'Test User',
    ),
  );

  // Create a mock implementation of the FirebaseService
  final mockFirebaseService = MockFirebaseService(mockAuth: mockAuth);

  // Create a container with the mocked dependencies
  final container = ProviderContainer(
    overrides: [
      firebaseServiceProvider.overrideWithValue(mockFirebaseService),
      userRepositoryProvider.overrideWithValue(MockUserRepository()),
    ],
  );

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('Splash screen shows Lumi text', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LumiApp(),
      ),
    );

    // Pump through splash delay and first navigation frame without waiting for
    // perpetual progress indicators/animations to settle.
    await tester.pump(const Duration(seconds: 3));

    // Verify that the app launches (checking for common UI elements)
    // The splash screen should show the app title
    expect(find.text('Lumi'), findsOneWidget);

    // Dispose and advance fake time so pending splash timers are drained.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });
}
