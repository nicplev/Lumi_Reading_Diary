import Flutter
import UIKit
import FirebaseAuth

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      if #available(iOS 13.0, *) {
        SinglePageDocumentScanner.register(with: controller)
      }
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
