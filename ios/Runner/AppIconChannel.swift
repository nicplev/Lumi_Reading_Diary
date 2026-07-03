import Flutter
import UIKit

/// Bridges UIApplication's alternate-app-icon API to Flutter so the app can
/// offer the Lumi icon pack. Alternate icon sets live in Assets.xcassets and
/// are declared via ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES in the
/// Runner build settings; iOS persists the applied icon across launches.
///
/// Registered via `FlutterPluginRegistrar` rather than a `FlutterViewController`
/// for the same reason as SinglePageDocumentScanner: in this scene-based app
/// the window does not exist yet during `didFinishLaunchingWithOptions`.
class AppIconChannel: NSObject {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "lumi/app_icon",
            binaryMessenger: registrar.messenger()
        )
        let instance = AppIconChannel()
        channel.setMethodCallHandler(instance.handle)
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isSupported":
            result(UIApplication.shared.supportsAlternateIcons)

        case "getAlternateIconName":
            // nil means the primary icon is active.
            result(UIApplication.shared.alternateIconName)

        case "setAlternateIconName":
            // iconName is nil (arrives as NSNull) to restore the primary icon.
            let args = call.arguments as? [String: Any]
            let iconName = args?["iconName"] as? String

            guard UIApplication.shared.supportsAlternateIcons else {
                result(FlutterError(
                    code: "UNSUPPORTED",
                    message: "Alternate icons are not supported on this device",
                    details: nil
                ))
                return
            }

            UIApplication.shared.setAlternateIconName(iconName) { error in
                // The completion queue is undocumented; results must be
                // delivered on the platform (main) thread.
                DispatchQueue.main.async {
                    if let error = error {
                        result(FlutterError(
                            code: "SET_FAILED",
                            message: error.localizedDescription,
                            details: iconName
                        ))
                    } else {
                        result(nil)
                    }
                }
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
