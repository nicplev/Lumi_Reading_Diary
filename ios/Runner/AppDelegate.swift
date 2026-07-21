import Flutter
import UIKit
import FirebaseAuth

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var bluetoothSettingsChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if #available(iOS 13.0, *) {
      // Register via FlutterPluginRegistrar (not via window.rootViewController).
      // In scene-based apps the window is created by the scene delegate, so it
      // is nil here at launch and the previous controller-based registration was
      // silently skipped — surfacing as MissingPluginException on the Dart side.
      if let registrar = self.registrar(forPlugin: "SinglePageDocumentScanner") {
        SinglePageDocumentScanner.register(with: registrar)
        NSLog("[CoverScanner] SinglePageDocumentScanner registered via FlutterPluginRegistrar")
      } else {
        NSLog("[CoverScanner] SKIPPED registration: registrar(forPlugin:) returned nil")
      }
    } else {
      NSLog("[CoverScanner] skipping native scanner registration (iOS < 13)")
    }
    if let registrar = self.registrar(forPlugin: "AppIconChannel") {
      AppIconChannel.register(with: registrar)
    } else {
      NSLog("[AppIcon] SKIPPED registration: registrar(forPlugin:) returned nil")
    }
    if let registrar = self.registrar(forPlugin: "HidKeyboardChannel") {
      HidKeyboardChannel.register(with: registrar)
    } else {
      NSLog("[HidKeyboard] SKIPPED registration: registrar(forPlugin:) returned nil")
    }
    if let registrar = self.registrar(forPlugin: "BluetoothSettingsChannel") {
      let channel = FlutterMethodChannel(
        name: "lumi/bluetooth_settings",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        guard call.method == "openBluetoothSettings" else {
          result(FlutterMethodNotImplemented)
          return
        }

        // UIKit only publishes an app-specific Settings URL; using it here is
        // what previously sent teachers to Lumi's permissions page. The
        // Bluetooth subpath below is best-effort: current iOS versions may
        // ignore the subpath and show Settings home, so Flutter presents the
        // one remaining "tap Bluetooth" instruction before opening it.
        guard let settingsURL = URL(string: "App-Prefs:root=Bluetooth") else {
          result("unavailable")
          return
        }
        UIApplication.shared.open(settingsURL, options: [:]) { opened in
          result(opened ? "systemSettings" : "unavailable")
        }
      }
      bluetoothSettingsChannel = channel
    } else {
      NSLog("[BluetoothSettings] SKIPPED registration: registrar(forPlugin:) returned nil")
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    // Forward lumi:// deep links from widget taps to Flutter (home_widget plugin handles dispatch)
    return super.application(app, open: url, options: options)
  }

  // Forward the APNs device token to Firebase Auth so phone verification
  // uses silent-push attestation instead of opening SFSafariViewController
  // for reCAPTCHA on real devices. firebase_messaging already calls
  // registerForRemoteNotifications() once notification permission is
  // granted, so this fires automatically — no extra wiring needed.
  // Simulator no-ops because it can't receive APNs tokens at all.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Auth.auth().setAPNSToken(deviceToken, type: .unknown)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  // Hand Firebase silent-push payloads back to Firebase Auth so it can
  // complete the silent verification handshake before
  // firebase_messaging's own handler sees them.
  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    if Auth.auth().canHandleNotification(userInfo) {
      completionHandler(.noData)
      return
    }
    super.application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)
  }
}
