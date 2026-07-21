import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Best-effort native detection for Bluetooth HID barcode scanners.
///
/// Keyboard-wedge scanners appear to the operating system as hardware
/// keyboards. Detection is deliberately advisory: null means the platform
/// cannot determine the state, and callers must keep scanner input enabled and
/// fall back to their existing UI heuristic.
class HidScannerConnectionService {
  static const MethodChannel _methodChannel =
      MethodChannel('lumi/hid_keyboard');
  static const EventChannel _eventChannel =
      EventChannel('lumi/hid_keyboard/events');

  static bool get _isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  /// Returns true or false only when the native platform affirmatively knows.
  /// Unsupported OS versions and channel failures return null (fail open).
  Future<bool?> isConnected() async {
    if (!_isSupportedPlatform) return null;
    try {
      return await _methodChannel.invokeMethod<bool>('isKeyboardConnected');
    } catch (_) {
      return null;
    }
  }

  /// Emits native connect/disconnect changes when supported.
  ///
  /// Channel errors are consumed so native detection can never interrupt the
  /// kiosk flow or disable keyboard-wedge input.
  Stream<bool> connectionChanges() {
    if (!_isSupportedPlatform) return const Stream<bool>.empty();
    return _eventChannel
        .receiveBroadcastStream()
        .where((event) => event is bool)
        .cast<bool>()
        .handleError((Object _, StackTrace __) {});
  }
}
