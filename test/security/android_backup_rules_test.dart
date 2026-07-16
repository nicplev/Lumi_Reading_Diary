import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android backup and device transfer exclude all Lumi app data', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final rules = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="false"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );

    final cloudBackup = _section(rules, 'cloud-backup');
    final deviceTransfer = _section(rules, 'device-transfer');
    const domains = <String>{
      'root',
      'file',
      'database',
      'sharedpref',
      'external',
      'device_root',
      'device_file',
      'device_database',
      'device_sharedpref',
    };

    for (final section in <String>[cloudBackup, deviceTransfer]) {
      for (final domain in domains) {
        expect(
          section,
          contains('<exclude domain="$domain" path="." />'),
          reason: '$domain must not be transferred or restored',
        );
      }
    }
  });
}

String _section(String xml, String name) {
  final match = RegExp(
    '<$name>([\\s\\S]*?)</$name>',
  ).firstMatch(xml);
  expect(match, isNotNull, reason: 'Missing <$name> extraction rules');
  return match!.group(1)!;
}
