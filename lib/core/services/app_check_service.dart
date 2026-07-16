import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// Activates Firebase App Check for the current platform.
///
/// Controlled by the `LUMI_APP_CHECK_ENABLED` dart-define. The supported
/// mobile release-build wrapper requires it to be true; debug runs may still
/// opt in explicitly while registering a revocable debug-provider token.
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

  /// Dart-define switch. It remains false for an ad-hoc raw `flutter run`, but
  /// `.dart_define.json` plus `scripts/flutter-build.sh` require it for every
  /// supported mobile release artifact.
  static const bool _enabled = bool.fromEnvironment(
    "LUMI_APP_CHECK_ENABLED",
    defaultValue: false,
  );

  static const String _webRecaptchaKey = String.fromEnvironment(
    "LUMI_APP_CHECK_RECAPTCHA_KEY",
    defaultValue: "",
  );

  // Optional, revocable credentials for physical debug builds. Keep the
  // values out of source control and pass them only via --dart-define while
  // testing. Release builds never select the debug providers.
  static const String _androidDebugToken = String.fromEnvironment(
    "LUMI_APP_CHECK_ANDROID_DEBUG_TOKEN",
    defaultValue: "",
  );

  static const String _appleDebugToken = String.fromEnvironment(
    "LUMI_APP_CHECK_APPLE_DEBUG_TOKEN",
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
            ? const AndroidDebugProvider(
                debugToken:
                    _androidDebugToken == "" ? null : _androidDebugToken,
              )
            : const AndroidPlayIntegrityProvider(),
        providerApple: kDebugMode
            ? const AppleDebugProvider(
                debugToken: _appleDebugToken == "" ? null : _appleDebugToken,
              )
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
