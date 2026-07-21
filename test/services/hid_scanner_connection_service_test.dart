import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/services/hid_scanner_connection_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('lumi/hid_keyboard');
  const eventMethodChannel = MethodChannel('lumi/hid_keyboard/events');
  const eventChannelName = 'lumi/hid_keyboard/events';
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final service = HidScannerConnectionService();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMockMethodCallHandler(eventMethodChannel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('isConnected passes through true, false, and unknown', () async {
    for (final value in <bool?>[true, false, null]) {
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        expect(call.method, 'isKeyboardConnected');
        return value;
      });

      expect(await service.isConnected(), value);
    }
  });

  test('isConnected degrades channel failures to unknown', () async {
    messenger.setMockMethodCallHandler(methodChannel, (_) async {
      throw PlatformException(code: 'native_failure');
    });

    expect(await service.isConnected(), isNull);
  });

  test('connectionChanges emits booleans and swallows native errors', () async {
    messenger.setMockMethodCallHandler(eventMethodChannel, (_) async => null);
    final values = <bool>[];
    final errors = <Object>[];
    final subscription = service.connectionChanges().listen(
          values.add,
          onError: errors.add,
        );
    await messenger.platformMessagesFinished;

    Future<void> send(ByteData data) async {
      await messenger.handlePlatformMessage(eventChannelName, data, null);
      await Future<void>.delayed(Duration.zero);
    }

    await send(codec.encodeSuccessEnvelope(true));
    await send(codec.encodeErrorEnvelope(
      code: 'stream_failure',
      message: 'temporary native error',
    ));
    await send(codec.encodeSuccessEnvelope(false));

    expect(values, <bool>[true, false]);
    expect(errors, isEmpty);
    await subscription.cancel();
  });

  test('non-mobile platforms return unknown without touching channels',
      () async {
    var methodCalled = false;
    var eventCalled = false;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    messenger.setMockMethodCallHandler(methodChannel, (_) async {
      methodCalled = true;
      return true;
    });
    messenger.setMockMethodCallHandler(eventMethodChannel, (_) async {
      eventCalled = true;
      return null;
    });

    expect(await service.isConnected(), isNull);
    expect(await service.connectionChanges().toList(), isEmpty);
    expect(methodCalled, isFalse);
    expect(eventCalled, isFalse);
  });
}
