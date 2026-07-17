import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumi_reading_tracker/core/services/remote_message_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDirectory;
  var sequence = 0;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('lumi_status_test_');
    Hive.init(hiveDirectory.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  RemoteMessageController controllerFor(http.Client client) {
    sequence += 1;
    return RemoteMessageController.forTest(
      endpoint: Uri.parse('https://status.example.test/status'),
      httpClient: client,
      pollInterval: const Duration(days: 1),
      cacheBoxName: 'remote_message_$sequence',
      dismissalsBoxName: 'dismissed_messages_$sequence',
    );
  }

  test('first successful refresh marks version configuration available',
      () async {
    final controller = controllerFor(MockClient((_) async {
      return http.Response(
        '{"version":1,"id":null,"message":null,"minAppVersion":"1.0.0"}',
        200,
      );
    }));

    expect(controller.configState, RemoteMessageConfigState.checking);
    await controller.initialize();

    expect(controller.configState, RemoteMessageConfigState.available);
    expect(controller.current?.minAppVersion, '1.0.0');
    await controller.dispose();
  });

  test('first unreachable refresh marks version configuration unavailable',
      () async {
    final controller = controllerFor(MockClient((_) async {
      throw const SocketException('offline');
    }));

    await controller.initialize();

    expect(controller.configState, RemoteMessageConfigState.unavailable);
    expect(controller.current, isNull);
    await controller.dispose();
  });

  test('known policy remains available through a later transient outage',
      () async {
    var offline = false;
    final controller = controllerFor(MockClient((_) async {
      if (offline) throw const SocketException('offline');
      return http.Response(
        '{"version":1,"id":"update","message":"Update",'
        '"minAppVersion":"2.0.0"}',
        200,
      );
    }));

    await controller.initialize();
    offline = true;
    await controller.refresh();

    expect(controller.configState, RemoteMessageConfigState.available);
    expect(controller.current?.minAppVersion, '2.0.0');
    await controller.dispose();
  });
}
