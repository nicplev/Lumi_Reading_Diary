import Flutter
import GameController
import UIKit

/// Reports whether iOS currently has a hardware keyboard connected. Bluetooth
/// HID barcode scanners register as keyboards, so this is a best-effort signal
/// for the kiosk's connection guidance; it never gates scanner input.
class HidKeyboardChannel: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private var observers: [NSObjectProtocol] = []

    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = HidKeyboardChannel()
        let methodChannel = FlutterMethodChannel(
            name: "lumi/hid_keyboard",
            binaryMessenger: registrar.messenger()
        )
        methodChannel.setMethodCallHandler(instance.handle)

        let eventChannel = FlutterEventChannel(
            name: "lumi/hid_keyboard/events",
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(instance)
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "isKeyboardConnected" else {
            result(FlutterMethodNotImplemented)
            return
        }

        if #available(iOS 14.0, *) {
            result(GCKeyboard.coalesced != nil)
        } else {
            // Unknown rather than false: older iOS versions cannot determine
            // the state, so Dart retains the existing fail-open heuristic.
            result(nil)
        }
    }

    func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        eventSink = events
        removeObservers()

        guard #available(iOS 14.0, *) else {
            return nil
        }

        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: .GCKeyboardDidConnect,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.emitCurrentState()
            },
            center.addObserver(
                forName: .GCKeyboardDidDisconnect,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                // Re-check the coalesced keyboard in case another hardware
                // keyboard remains connected.
                self?.emitCurrentState()
            },
        ]
        emitCurrentState()
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        removeObservers()
        return nil
    }

    @available(iOS 14.0, *)
    private func emitCurrentState() {
        eventSink?(GCKeyboard.coalesced != nil)
    }

    private func removeObservers() {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }

    deinit {
        removeObservers()
    }
}
