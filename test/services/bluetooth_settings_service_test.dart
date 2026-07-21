import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/services/bluetooth_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('lumi/bluetooth_settings_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('maps the native Bluetooth destination', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'openBluetoothSettings');
      return 'bluetooth';
    });

    final result = await BluetoothSettingsService(channel: channel)
        .openBluetoothSettings();

    expect(result, BluetoothSettingsDestination.bluetooth);
  });

  test('maps the native system Settings fallback', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => 'systemSettings');

    final result = await BluetoothSettingsService(channel: channel)
        .openBluetoothSettings();

    expect(result, BluetoothSettingsDestination.systemSettings);
  });

  test('fails closed when the native channel is unavailable', () async {
    final result = await BluetoothSettingsService(channel: channel)
        .openBluetoothSettings();

    expect(result, BluetoothSettingsDestination.unavailable);
  });
}
