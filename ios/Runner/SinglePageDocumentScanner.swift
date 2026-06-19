import Flutter
import UIKit
import VisionKit

/// A custom document scanner that takes only the first captured page.
///
/// VisionKit's VNDocumentCameraViewController does not support auto-dismissal
/// after N pages. The user must tap the Save (checkmark) button to finish.
/// This handler ensures we only return the first page regardless of how many
/// the user captured, and writes it as a compressed JPEG to the temp directory.
@available(iOS 13.0, *)
class SinglePageDocumentScanner: NSObject, VNDocumentCameraViewControllerDelegate {
    private var result: FlutterResult?
    private var viewController: VNDocumentCameraViewController?
    private var jpgCompressionQuality: Double = 0.92

    static func register(with controller: FlutterViewController) {
        let channel = FlutterMethodChannel(
            name: "lumi/single_page_document_scanner",
            binaryMessenger: controller.binaryMessenger
        )
        let instance = SinglePageDocumentScanner()
        channel.setMethodCallHandler(instance.handle)
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        NSLog("[CoverScanner] handle() called method=%@", call.method)
        guard call.method == "scanSinglePage" else {
            result(FlutterMethodNotImplemented)
            return
        }

        if let args = call.arguments as? [String: Any],
           let quality = args["jpgCompressionQuality"] as? Double {
            jpgCompressionQuality = quality
        }

        self.result = result

        guard VNDocumentCameraViewController.isSupported else {
            NSLog("[CoverScanner] VNDocumentCameraViewController.isSupported=false; returning UNAVAILABLE")
            result(FlutterError(
                code: "UNAVAILABLE",
                message: "Document camera is not available on this device",
                details: nil
            ))
            return
        }

        let scanner = VNDocumentCameraViewController()
        scanner.delegate = self
        self.viewController = scanner

        // Scene-aware key-window lookup. `UIApplication.shared.keyWindow` is
        // deprecated since iOS 13 and returns nil in scene-based apps — which
        // this app is (the WidgetKit extension forces scene lifecycle). The
        // pre-deprecation API was what was silently failing on real device.
        guard let window = Self.activeKeyWindow(),
              var topController = window.rootViewController else {
            NSLog("[CoverScanner] no active key window or rootViewController; returning NO_VIEW_CONTROLLER")
            result(FlutterError(
                code: "NO_VIEW_CONTROLLER",
                message: "Could not find root view controller",
                details: nil
            ))
            return
        }

        // Walk to the topmost presented controller.
        while let presented = topController.presentedViewController {
            topController = presented
        }
        NSLog("[CoverScanner] presenting VNDocumentCameraViewController on %@",
              String(describing: type(of: topController)))
        topController.present(scanner, animated: true)
    }

    /// Returns the foreground-active scene's key window, falling back to the
    /// first window of any foreground scene. Replaces `UIApplication.shared.keyWindow`,
    /// which is deprecated and unreliable under scene-based app lifecycle.
    private static func activeKeyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
        let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            ?? scenes.first(where: { $0.activationState == .foregroundInactive }) as? UIWindowScene
            ?? scenes.first as? UIWindowScene
        guard let scene = activeScene else { return nil }
        return scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
    }

    // MARK: - VNDocumentCameraViewControllerDelegate

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFinishWith scan: VNDocumentCameraScan
    ) {
        guard scan.pageCount > 0 else {
            dismiss()
            result?(nil)
            result = nil
            return
        }

        let image = scan.imageOfPage(at: 0)
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "cover_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        let url = tempDir.appendingPathComponent(filename)

        if let data = image.jpegData(compressionQuality: jpgCompressionQuality) {
            try? data.write(to: url)
            dismiss()
            result?([url.path])
        } else {
            dismiss()
            result?(nil)
        }
        result = nil
    }

    func documentCameraViewControllerDidCancel(
        _ controller: VNDocumentCameraViewController
    ) {
        dismiss()
        result?(nil)
        result = nil
    }

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFailWithError error: Error
    ) {
        dismiss()
        result?(FlutterError(
            code: "SCAN_ERROR",
            message: error.localizedDescription,
            details: nil
        ))
        result = nil
    }

    // MARK: - Helpers

    private func dismiss() {
        viewController?.dismiss(animated: true)
        viewController = nil
    }
}
