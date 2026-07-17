import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/tour/lumi_app_tour.dart';

void main() {
  group('availableLumiTourSteps', () {
    test('hides both widget steps on Android', () {
      final parent = availableLumiTourSteps(
        LumiTourDefinitions.parent,
        isWeb: false,
        platform: TargetPlatform.android,
      );
      final teacher = availableLumiTourSteps(
        LumiTourDefinitions.teacher,
        isWeb: false,
        platform: TargetPlatform.android,
      );

      expect(parent.any((step) => step.id == 'widget'), isFalse);
      expect(teacher.any((step) => step.id == 'widget'), isFalse);
      expect(parent.length, LumiTourDefinitions.parent.steps.length - 1);
      expect(teacher.length, LumiTourDefinitions.teacher.steps.length - 1);
    });

    test('keeps both widget steps on iOS', () {
      final parent = availableLumiTourSteps(
        LumiTourDefinitions.parent,
        isWeb: false,
        platform: TargetPlatform.iOS,
      );
      final teacher = availableLumiTourSteps(
        LumiTourDefinitions.teacher,
        isWeb: false,
        platform: TargetPlatform.iOS,
      );

      expect(parent.any((step) => step.id == 'widget'), isTrue);
      expect(teacher.any((step) => step.id == 'widget'), isTrue);
    });

    test('does not expose iOS-only steps on web', () {
      final steps = availableLumiTourSteps(
        LumiTourDefinitions.parent,
        isWeb: true,
        platform: TargetPlatform.iOS,
      );

      expect(steps.any((step) => step.iosOnly), isFalse);
    });
  });
}
