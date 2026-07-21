import 'package:flutter/services.dart';

enum BluetoothSettingsDestination {
  /// The operating system opened its Bluetooth device-management page.
  bluetooth,

  /// The operating system opened its main Settings page. This is the closest
  /// route available on current iOS versions, which do not expose a public
  /// Bluetooth-pane deep link.
  systemSettings,

  /// No supported system-settings destination could be opened.
  unavailable,
}

abstract class BluetoothSettingsController {
  Future<BluetoothSettingsDestination> openBluetoothSettings();
}

/// Opens the operating system's Bluetooth pairing settings through a small
/// native channel. Android supports a dedicated Bluetooth settings intent;
/// iOS can only make a best-effort jump into the system Settings app.
class BluetoothSettingsService implements BluetoothSettingsController {
  BluetoothSettingsService({
    MethodChannel channel = const MethodChannel('lumi/bluetooth_settings'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<BluetoothSettingsDestination> openBluetoothSettings() async {
    try {
      final destination =
          await _channel.invokeMethod<String>('openBluetoothSettings');
      return switch (destination) {
        'bluetooth' => BluetoothSettingsDestination.bluetooth,
        'systemSettings' => BluetoothSettingsDestination.systemSettings,
        _ => BluetoothSettingsDestination.unavailable,
      };
    } on PlatformException {
      return BluetoothSettingsDestination.unavailable;
    } on MissingPluginException {
      return BluetoothSettingsDestination.unavailable;
    }
  }
}
