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

        guard let window = UIApplication.shared.keyWindow,
              var topController = window.rootViewController else {
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
        topController.present(scanner, animated: true)
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
