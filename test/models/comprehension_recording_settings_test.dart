import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/models/comprehension_recording_settings.dart';

void main() {
  test('audio settings default to disabled production collection', () {
    final settings = ComprehensionRecordingSettings.fromMap(null);

    expect(settings.enabled, isFalse);
    expect(settings.previewOnly, isFalse);
    expect(settings.toMap(), {'enabled': false});
  });

  test('synthetic demo preview is explicit and round-trips', () {
    final settings = ComprehensionRecordingSettings.fromMap({
      'enabled': true,
      'demoPreviewOnly': true,
    });

    expect(settings.enabled, isTrue);
    expect(settings.previewOnly, isTrue);
    expect(settings.toMap(), {
      'enabled': true,
      'demoPreviewOnly': true,
    });
  });
}
