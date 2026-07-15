import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/models/user_model.dart';
import 'package:lumi_reading_tracker/screens/settings/account_screen.dart';
import 'package:lumi_reading_tracker/services/account_deletion_service.dart';

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

Future<void> pumpAccount(
  WidgetTester tester,
  UserRole role,
) async {
  await tester.pumpWidget(MaterialApp(
    home: AccountScreen(
      user: user(role),
      deletionService: serviceWithStatus(),
      firestore: FakeFirebaseFirestore(),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('parent sees account deletion but not student deletion',
      (tester) async {
    await pumpAccount(tester, UserRole.parent);

    expect(find.byKey(const Key('delete-account-button')), findsOneWidget);
    expect(find.byKey(const Key('delete-student-button')), findsNothing);
    expect(find.textContaining("does not delete your child's school record"),
        findsOneWidget);
  });

  testWidgets('teacher sees both account and student deletion controls',
      (tester) async {
    await pumpAccount(tester, UserRole.teacher);

    expect(find.byKey(const Key('delete-account-button')), findsOneWidget);
    expect(find.byKey(const Key('delete-student-button')), findsOneWidget);
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
}
