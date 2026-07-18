import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/screens/auth/terms_acceptance_screen.dart';

void main() {
  testWidgets('offers retry before sign-out in the current Lumi UI',
      (tester) async {
    var retries = 0;
    var signOuts = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TermsAccountLoadError(
            onRetry: () => retries++,
            onSignOut: () => signOuts++,
          ),
        ),
      ),
    );

    expect(find.text("Let's reconnect your account"), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byKey(const Key('terms-account-retry')), findsOneWidget);
    expect(find.byKey(const Key('terms-account-sign-out')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('terms-account-retry')));
    await tester.tap(find.byKey(const Key('terms-account-retry')));
    await tester.ensureVisible(find.byKey(const Key('terms-account-sign-out')));
    await tester.tap(find.byKey(const Key('terms-account-sign-out')));
    expect(retries, 1);
    expect(signOuts, 1);
  });
}
