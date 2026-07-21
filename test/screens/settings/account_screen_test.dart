import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/models/user_model.dart';
import 'package:lumi_reading_tracker/screens/settings/account_screen.dart';
import 'package:lumi_reading_tracker/services/account_deletion_service.dart';
import 'package:lumi_reading_tracker/services/account_reauthentication_service.dart';
import 'package:lumi_reading_tracker/services/diagnostics_preferences_service.dart';

class FakeDiagnosticsController implements DiagnosticsSettingsController {
  FakeDiagnosticsController({
    this.analyticsEnabled = false,
    this.crashReportsEnabled = false,
  });

  bool analyticsEnabled;
  bool crashReportsEnabled;

  @override
  Future<DiagnosticsPreferences> load() async => DiagnosticsPreferences(
        analyticsEnabled: analyticsEnabled,
        crashReportsEnabled: crashReportsEnabled,
      );

  @override
  Future<void> setAnalyticsEnabled(bool enabled) async {
    analyticsEnabled = enabled;
  }

  @override
  Future<void> setCrashReportsEnabled(bool enabled) async {
    crashReportsEnabled = enabled;
  }
}

UserModel user(UserRole role) => UserModel(
      id: '${role.name}_1',
      email: '${role.name}@example.test',
      fullName: 'Test User',
      role: role,
      schoolId: 'school_1',
      createdAt: DateTime(2026),
    );

AccountDeletionService serviceWithStatus({String status = 'pending'}) {
  return AccountDeletionService(
    callableInvoker: (name, arguments) async {
      if (name == 'getMyDeletionStatus') return {'job': null};
      return {
        'jobId': 'job_hash',
        'kind': 'account',
        'status': status,
        'attemptCount': 1,
        'retrying': false,
      };
    },
  );
}

class FakeReauthenticationController
    implements AccountReauthenticationController {
  FakeReauthenticationController({
    this.method = AccountReauthenticationMethod.password,
    this.identifier = 'parent@example.test',
    this.passwordFailures = 0,
  });

  final AccountReauthenticationMethod method;
  final String identifier;
  int passwordFailures;
  final passwords = <String>[];
  final smsCodes = <String>[];
  final providers = <AccountReauthenticationMethod>[];

  @override
  Future<AccountReauthenticationProfile> loadProfile() async =>
      AccountReauthenticationProfile(
        method: method,
        identifier: identifier,
      );

  @override
  Future<void> reauthenticateWithPassword(
    String password,
    ReauthenticationCodePrompt promptForCode,
  ) async {
    passwords.add(password);
    if (passwordFailures > 0) {
      passwordFailures -= 1;
      throw const AccountReauthenticationException('invalid-credential');
    }
  }

  @override
  Future<void> reauthenticateWithPhone(
    ReauthenticationCodePrompt promptForCode,
  ) async {
    final code = await promptForCode(identifier, () async {}, null);
    if (code == null) {
      throw const AccountReauthenticationException('cancelled');
    }
    smsCodes.add(code);
  }

  @override
  Future<void> reauthenticateWithProvider(
    AccountReauthenticationMethod method,
  ) async {
    providers.add(method);
  }
}

AccountDeletionService recentLoginThenStatusService({
  required void Function() onRequest,
}) {
  var attempts = 0;
  return AccountDeletionService(
    callableInvoker: (name, arguments) async {
      if (name == 'getMyDeletionStatus') return {'job': null};
      onRequest();
      attempts += 1;
      if (attempts == 1) {
        throw const AccountDeletionException(
          'failed-precondition',
          'recent-login-required',
        );
      }
      return {
        'jobId': 'job_hash',
        'kind': 'account',
        'status': 'pending',
        'attemptCount': 0,
        'retrying': false,
      };
    },
  );
}

Future<void> pumpAccount(
  WidgetTester tester,
  UserRole role, {
  DiagnosticsSettingsController? diagnosticsController,
  AccountDeletionService? deletionService,
  AccountReauthenticationController? reauthenticationController,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: AccountScreen(
      user: user(role),
      deletionService: deletionService ?? serviceWithStatus(),
      reauthenticationController:
          reauthenticationController ?? FakeReauthenticationController(),
      diagnosticsController:
          diagnosticsController ?? FakeDiagnosticsController(),
      firestore: FakeFirebaseFirestore(),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('internal deletion failures use actionable copy', () {
    final message = accountDeletionErrorMessage(
      const AccountDeletionException('internal', 'INTERNAL'),
    );

    expect(message, isNot(contains('INTERNAL')));
    expect(message, contains('could not finish'));
    expect(message, contains('check its status'));
  });

  testWidgets('parent sees account deletion but not student deletion',
      (tester) async {
    await pumpAccount(tester, UserRole.parent);

    expect(find.byKey(const Key('delete-account-button')), findsOneWidget);
    expect(find.byKey(const Key('delete-student-button')), findsNothing);
    expect(find.textContaining("does not delete your child's school record"),
        findsOneWidget);
  });

  testWidgets('teacher sees account deletion but not student deletion',
      (tester) async {
    await pumpAccount(tester, UserRole.teacher);

    expect(find.byKey(const Key('delete-account-button')), findsOneWidget);
    expect(find.byKey(const Key('delete-student-button')), findsNothing);
  });

  testWidgets('school admin sees both account and student deletion controls',
      (tester) async {
    await pumpAccount(tester, UserRole.schoolAdmin);

    expect(find.byKey(const Key('delete-account-button')), findsOneWidget);
    expect(find.byKey(const Key('delete-student-button')), findsOneWidget);
  });

  testWidgets('optional diagnostics default off for parent accounts',
      (tester) async {
    await pumpAccount(tester, UserRole.parent);
    await tester.scrollUntilVisible(
      find.byKey(const Key('optional-analytics-toggle')),
      400,
    );

    final analytics = tester.widget<SwitchListTile>(
        find.byKey(const Key('optional-analytics-toggle')));
    final crashes = tester.widget<SwitchListTile>(
        find.byKey(const Key('optional-crash-reports-toggle')));
    expect(analytics.value, isFalse);
    expect(crashes.value, isFalse);
  });

  testWidgets('teacher can opt in and withdraw each diagnostics choice',
      (tester) async {
    final controller = FakeDiagnosticsController();
    await pumpAccount(
      tester,
      UserRole.teacher,
      diagnosticsController: controller,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('optional-analytics-toggle')),
      500,
    );

    await tester.tap(find.byKey(const Key('optional-analytics-toggle')));
    await tester.pumpAndSettle();
    expect(controller.analyticsEnabled, isTrue);

    await tester.tap(find.byKey(const Key('optional-crash-reports-toggle')));
    await tester.pumpAndSettle();
    expect(controller.crashReportsEnabled, isTrue);

    await tester.tap(find.byKey(const Key('optional-analytics-toggle')));
    await tester.pumpAndSettle();
    expect(controller.analyticsEnabled, isFalse);
  });

  testWidgets('account deletion stays disabled until exact DELETE confirmation',
      (tester) async {
    await pumpAccount(tester, UserRole.parent);
    await tester.tap(find.byKey(const Key('delete-account-button')));
    await tester.pumpAndSettle();

    final confirm = find.byKey(const Key('confirm-account-deletion'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('account-delete-confirmation')),
      'delete',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('account-delete-confirmation')),
      'DELETE',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
  });

  testWidgets(
      'stale password session reauthenticates inline and retries deletion',
      (tester) async {
    var requests = 0;
    final reauthentication = FakeReauthenticationController();
    await pumpAccount(
      tester,
      UserRole.parent,
      deletionService: recentLoginThenStatusService(
        onRequest: () => requests += 1,
      ),
      reauthenticationController: reauthentication,
    );

    await tester.tap(find.byKey(const Key('delete-account-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('account-delete-confirmation')),
      'DELETE',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-account-deletion')));
    await tester.pumpAndSettle();

    expect(find.text('Confirm it\'s you'), findsOneWidget);
    expect(find.byKey(const Key('account-reauth-email')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('account-reauth-email'))).data,
      'parent@example.test',
    );
    expect(requests, 1);

    await tester.enterText(
      find.byKey(const Key('account-reauth-password')),
      'correct horse battery staple',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('verify-and-delete-account')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(reauthentication.passwords, ['correct horse battery staple']);
    expect(requests, 2);
    expect(find.byKey(const Key('deletion-error')), findsNothing);
  });

  testWidgets('wrong password stays inside generic reauthentication flow',
      (tester) async {
    var requests = 0;
    final reauthentication = FakeReauthenticationController(
      passwordFailures: 1,
    );
    await pumpAccount(
      tester,
      UserRole.teacher,
      deletionService: recentLoginThenStatusService(
        onRequest: () => requests += 1,
      ),
      reauthenticationController: reauthentication,
    );

    await tester.tap(find.byKey(const Key('delete-account-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('account-delete-confirmation')),
      'DELETE',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-account-deletion')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('account-reauth-password')),
      'wrong password',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('verify-and-delete-account')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Those details were not correct. Please try again.'),
        findsOneWidget);
    expect(find.textContaining('invalid-credential'), findsNothing);
    expect(requests, 1);

    await tester.enterText(
      find.byKey(const Key('account-reauth-password')),
      'correct password',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('verify-and-delete-account')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(requests, 2);
    expect(reauthentication.passwords, ['wrong password', 'correct password']);
  });

  testWidgets('phone-primary session verifies an SMS code before retrying',
      (tester) async {
    var requests = 0;
    final reauthentication = FakeReauthenticationController(
      method: AccountReauthenticationMethod.phone,
      identifier: '+61400000000',
    );
    await pumpAccount(
      tester,
      UserRole.parent,
      deletionService: recentLoginThenStatusService(
        onRequest: () => requests += 1,
      ),
      reauthenticationController: reauthentication,
    );

    await tester.tap(find.byKey(const Key('delete-account-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('account-delete-confirmation')),
      'DELETE',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-account-deletion')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('send-account-reauth-code')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('account-reauth-sms-code')),
      '123456',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('verify-account-reauth-code')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(reauthentication.smsCodes, ['123456']);
    expect(requests, 2);
  });

  testWidgets('federated session uses its provider before retrying',
      (tester) async {
    var requests = 0;
    final reauthentication = FakeReauthenticationController(
      method: AccountReauthenticationMethod.google,
      identifier: 'parent@example.test',
    );
    await pumpAccount(
      tester,
      UserRole.parent,
      deletionService: recentLoginThenStatusService(
        onRequest: () => requests += 1,
      ),
      reauthenticationController: reauthentication,
    );

    await tester.tap(find.byKey(const Key('delete-account-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('account-delete-confirmation')),
      'DELETE',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-account-deletion')));
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('continue-account-provider-reauth')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(reauthentication.providers, [AccountReauthenticationMethod.google]);
    expect(requests, 2);
  });

  testWidgets('cancelling inline reauthentication does not retry deletion',
      (tester) async {
    var requests = 0;
    await pumpAccount(
      tester,
      UserRole.parent,
      deletionService: recentLoginThenStatusService(
        onRequest: () => requests += 1,
      ),
      reauthenticationController: FakeReauthenticationController(),
    );

    await tester.tap(find.byKey(const Key('delete-account-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('account-delete-confirmation')),
      'DELETE',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-account-deletion')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    expect(requests, 1);
    expect(find.byKey(const Key('deletion-error')), findsNothing);
  });
}
