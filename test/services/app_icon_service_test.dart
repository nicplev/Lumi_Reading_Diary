import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/services/app_icon_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('lumi/app_icon');
  final binaryMessenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  MethodCall? lastCall;

  void mockChannel(dynamic Function(MethodCall call) handler) {
    binaryMessenger.setMockMethodCallHandler(channel, (call) async {
      lastCall = call;
      return handler(call);
    });
  }

  setUp(() {
    lastCall = null;
    // Everything below exercises the iOS path unless a test says otherwise.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() {
    binaryMessenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  group('kLumiAppIcons catalog', () {
    test('has 12 icons with unique ids and iOS names', () {
      expect(kLumiAppIcons, hasLength(12));
      expect(kLumiAppIcons.map((i) => i.id).toSet(), hasLength(12));
      final iosNames =
          kLumiAppIcons.map((i) => i.iosIconName).whereType<String>();
      expect(iosNames.toSet(), hasLength(11));
    });

    test('exactly one default icon and it is listed first', () {
      expect(kLumiAppIcons.where((i) => i.isDefault), hasLength(1));
      expect(kLumiAppIcons.first.isDefault, isTrue);
      expect(kLumiAppIcons.first.id, 'red_face');
    });

    test('every icon has a generated preview asset on disk', () {
      for (final icon in kLumiAppIcons) {
        expect(File(icon.previewAsset).existsSync(), isTrue,
            reason: '${icon.previewAsset} missing — '
                'run scripts/generate_app_icons.py');
      }
    });

    test('alternate names match the Xcode build setting and iconsets', () {
      final pbxproj =
          File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      final match = RegExp(
              r'ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = "([^"]+)";')
          .firstMatch(pbxproj);
      expect(match, isNotNull,
          reason: 'ALTERNATE_APPICON_NAMES build setting missing');

      final namesInXcode = match!.group(1)!.split(' ').toSet();
      final namesInCatalog = kLumiAppIcons
          .map((i) => i.iosIconName)
          .whereType<String>()
          .toSet();
      expect(namesInXcode, namesInCatalog);

      for (final name in namesInCatalog) {
        final iconset = Directory('ios/Runner/Assets.xcassets/$name.appiconset');
        expect(File('${iconset.path}/icon_1024.png').existsSync(), isTrue,
            reason: '$name.appiconset missing its 1024px icon');
        expect(File('${iconset.path}/Contents.json').existsSync(), isTrue,
            reason: '$name.appiconset missing Contents.json');
      }
    });
  });

  group('AppIconService', () {
    final service = AppIconService();

    test('currentIcon resolves the reported alternate name', () async {
      mockChannel((call) => 'AppIconBlueLumi');
      final icon = await service.currentIcon();
      expect(icon.id, 'blue_lumi');
      expect(lastCall?.method, 'getAlternateIconName');
    });

    test('currentIcon maps null (primary icon) to the default entry',
        () async {
      mockChannel((call) => null);
      final icon = await service.currentIcon();
      expect(icon.id, 'red_face');
    });

    test('currentIcon falls back to default for names not in the catalog',
        () async {
      mockChannel((call) => 'AppIconRemovedInThisVersion');
      final icon = await service.currentIcon();
      expect(icon.isDefault, isTrue);
    });

    test('setIcon sends the alternate iconset name', () async {
      mockChannel((call) => null);
      final pink = kLumiAppIcons.singleWhere((i) => i.id == 'pink_lumi');
      await service.setIcon(pink);
      expect(lastCall?.method, 'setAlternateIconName');
      expect(lastCall?.arguments, {'iconName': 'AppIconPinkLumi'});
    });

    test('setIcon sends null to restore the primary icon', () async {
      mockChannel((call) => null);
      await service.setIcon(kLumiAppIcons.first);
      expect(lastCall?.arguments, {'iconName': null});
    });

    test('setIcon surfaces native failures as PlatformException', () async {
      mockChannel((call) =>
          throw PlatformException(code: 'SET_FAILED', message: 'nope'));
      expect(
        () => service.setIcon(kLumiAppIcons.last),
        throwsA(isA<PlatformException>()),
      );
    });

    test('isSupported asks iOS', () async {
      mockChannel((call) => true);
      expect(await service.isSupported(), isTrue);
      expect(lastCall?.method, 'isSupported');
    });

    test('isSupported is false on non-iOS platforms without a channel call',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      mockChannel((call) => true);
      expect(await service.isSupported(), isFalse);
      expect(lastCall, isNull);
    });
  });
}
