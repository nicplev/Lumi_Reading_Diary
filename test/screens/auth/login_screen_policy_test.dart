import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/models/user_model.dart';
import 'package:lumi_reading_tracker/screens/auth/login_screen.dart';

void main() {
  test('school administrators skip all mobile post-login setup', () {
    expect(
      LoginScreen.shouldPerformMobilePostLoginSetup(UserRole.schoolAdmin),
      isFalse,
    );
  });

  test('teacher and parent sign-ins retain mobile post-login setup', () {
    expect(
      LoginScreen.shouldPerformMobilePostLoginSetup(UserRole.teacher),
      isTrue,
    );
    expect(
      LoginScreen.shouldPerformMobilePostLoginSetup(UserRole.parent),
      isTrue,
    );
  });
}
