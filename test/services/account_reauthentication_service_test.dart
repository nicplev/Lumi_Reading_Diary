import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/services/account_reauthentication_service.dart';

void main() {
  test('password provider is preferred for linked password accounts', () {
    expect(
      accountReauthenticationMethodForProviders(
        const ['phone', 'google.com', 'password'],
      ),
      AccountReauthenticationMethod.password,
    );
  });

  test('current and future sign-in providers map to the correct flow', () {
    expect(
      accountReauthenticationMethodForProviders(const ['phone']),
      AccountReauthenticationMethod.phone,
    );
    expect(
      accountReauthenticationMethodForProviders(const ['google.com']),
      AccountReauthenticationMethod.google,
    );
    expect(
      accountReauthenticationMethodForProviders(const ['apple.com']),
      AccountReauthenticationMethod.apple,
    );
    expect(
      accountReauthenticationMethodForProviders(const ['custom']),
      AccountReauthenticationMethod.unsupported,
    );
  });

  test('credential failures use generic copy without backend details', () {
    final message = accountReauthenticationErrorMessage(
      const AccountReauthenticationException('invalid-credential'),
    );

    expect(message, 'Those details were not correct. Please try again.');
    expect(message, isNot(contains('credential')));
  });

  test('unsupported providers fail closed to a fresh full login', () {
    final message = accountReauthenticationErrorMessage(
      const AccountReauthenticationException('unsupported-provider'),
    );

    expect(message, contains('Sign out and sign back in'));
  });
}
