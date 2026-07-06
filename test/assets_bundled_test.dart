import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the asset paths referenced with literal strings outside the
/// character registry — folder renames or pubspec omissions surface here
/// instead of as blank images at runtime.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parent-header and empty-state artwork are bundled', () async {
    await rootBundle.load('assets/characters/red lumi (default).png');
    await rootBundle.load('assets/UI Lumi/lumi welcome.png');
    await rootBundle.load('assets/UI Lumi/password+lock.png');
  });
}
