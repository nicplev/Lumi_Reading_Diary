import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lumi_reading_tracker/core/auth/sign_out_flow.dart';
import 'package:mockito/mockito.dart';

import '../../helpers/mock_firebase_service.dart';

void main() {
  testWidgets('keeps login unavailable until sign-out cleanup completes',
      (tester) async {
    final service = MockFirebaseService();
    final cleanupCompleter = Completer<void>();
    var signOutHookCalled = false;

    when(service.signOut(afterAuthSignOut: anyNamed('afterAuthSignOut')))
        .thenAnswer((invocation) async {
      final hook = invocation.namedArguments[#afterAuthSignOut] as Future<void>
          Function()?;
      signOutHookCalled = true;
      await hook?.call();
      await cleanupCompleter.future;
    });

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  unawaited(
                    signOutAndNavigateToLogin(
                      context,
                      firebaseService: service,
                    ),
                  );
                },
                child: const Text('Sign out'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/auth/signing-out',
          builder: (context, state) => const Scaffold(
            body: Center(child: Text('Signing out route')),
          ),
        ),
        GoRoute(
          path: '/auth/login',
          builder: (context, state) => const Scaffold(
            body: Center(child: Text('Login route')),
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await tester.tap(find.text('Sign out'));
    await tester.pump();
    await tester.pump();

    expect(signOutHookCalled, isTrue);
    expect(find.text('Signing out route'), findsOneWidget);
    expect(find.text('Login route'), findsNothing);

    cleanupCompleter.complete();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Login route'), findsOneWidget);
  });
}
