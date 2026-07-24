import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/screens/teacher/isbn_scanner_screen.dart';

void main() {
  group('isbnCameraScanWindowFor', () {
    test('is a 260×180 rectangle sitting slightly above centre', () {
      final rect = isbnCameraScanWindowFor(const Size(400, 700));

      expect(rect.width, 260);
      expect(rect.height, 180);
      expect(rect.left, 70);
      // Matches the old Alignment(0, -0.12) overlay: (700 - 180) * 0.44.
      expect(rect.top, closeTo(228.8, 0.0001));
    });

    test('sits above the surface centre', () {
      const surface = Size(400, 700);
      final rect = isbnCameraScanWindowFor(surface);

      expect(rect.center.dx, surface.width / 2);
      expect(rect.center.dy, lessThan(surface.height / 2));
    });

    test('shrinks to fit a surface smaller than the reticle', () {
      final rect = isbnCameraScanWindowFor(const Size(200, 120));

      expect(rect, const Rect.fromLTWH(0, 0, 200, 120));
    });

    test('stays inside the camera surface', () {
      for (final surface in const <Size>[
        Size(320, 480),
        Size(430, 900),
        Size(834, 1112),
        Size(260, 180),
        Size(180, 260),
      ]) {
        final rect = isbnCameraScanWindowFor(surface);
        expect(rect.left, greaterThanOrEqualTo(0), reason: '$surface');
        expect(rect.top, greaterThanOrEqualTo(0), reason: '$surface');
        expect(rect.right, lessThanOrEqualTo(surface.width), reason: '$surface');
        expect(
          rect.bottom,
          lessThanOrEqualTo(surface.height),
          reason: '$surface',
        );
      }
    });
  });
}
