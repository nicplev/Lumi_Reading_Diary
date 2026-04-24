import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// Activates Firebase App Check for the current platform.
///
/// Kept opt-in via the `LUMI_APP_CHECK_ENABLED` dart-define so the code can
/// ship to production without risk — attestation only turns on once every
/// platform has been wired and the server-side env var
/// `IMPERSONATION_APP_CHECK_ENFORCED` is also flipped to `true`.
///
/// Build with:
///   flutter run --dart-define=LUMI_APP_CHECK_ENABLED=true \
///               --dart-define=LUMI_APP_CHECK_RECAPTCHA_KEY=`<web-key>`
///
/// Web requires a reCAPTCHA Enterprise site key. iOS/Android use DeviceCheck/
/// App Attest / Play Integrity which are keyless — register the bundle ID +
/// SHA-256 in the Firebase console's App Check page first.
///
/// In debug mode, the Firebase SDK auto-injects the debug provider and prints
/// a debug token in the console. Register that token in the console for
/// local testing, or the debug build will be rejected once enforcement is on.
class AppCheckService {
  AppCheckService._();

  /// Dart-define switch — default OFF so ordinary `flutter run`/`flutter build`
  /// skip activation. Flip true for the attested build.
  static const bool _enabled = bool.fromEnvironment(
    "LUMI_APP_CHECK_ENABLED",
    defaultValue: false,
  );

  static const String _webRecaptchaKey = String.fromEnvironment(
    "LUMI_APP_CHECK_RECAPTCHA_KEY",
    defaultValue: "",
  );

  /// Call once during startup, after `Firebase.initializeApp`. Safe to call
  /// when disabled — returns early without touching the SDK.
  static Future<void> initialize() async {
    if (!_enabled) {
      debugPrint("[AppCheck] disabled (LUMI_APP_CHECK_ENABLED != true)");
      return;
    }
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
        providerApple: kDebugMode
            ? const AppleDebugProvider()
            : const AppleAppAttestWithDeviceCheckFallbackProvider(),
        providerWeb: _webRecaptchaKey.isEmpty
            ? null
            : ReCaptchaEnterpriseProvider(_webRecaptchaKey),
      );
      debugPrint("[AppCheck] activated");
    } catch (e) {
      // Never crash the app over an attestation problem.
      debugPrint("[AppCheck] activation failed: $e");
    }
  }
}
