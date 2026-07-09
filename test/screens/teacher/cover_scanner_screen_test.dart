import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/screens/teacher/cover_scanner_screen.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  group('useDirectIosDocumentScanner', () {
    test('uses the direct document scanner path on iOS', () {
      expect(
        useDirectIosDocumentScanner(TargetPlatform.iOS),
        isTrue,
      );
      expect(
        useDirectIosDocumentScanner(TargetPlatform.android),
        isFalse,
      );
    });
  });

  group('coverCaptureFailureFor', () {
    test('prefers settings guidance when camera access is blocked', () {
      final failure = coverCaptureFailureFor(
        error: Exception('Permission not granted'),
        cameraStatus: PermissionStatus.permanentlyDenied,
      );

      expect(failure.allowOpenSettings, isTrue);
      expect(failure.allowGalleryFallback, isTrue);
      expect(failure.allowCameraFallback, isTrue);
      expect(failure.message, contains('Take Photo Instead'));
    });

    test('offers fallback capture when document scanner is unavailable', () {
      final failure = coverCaptureFailureFor(
        error: PlatformException(code: 'UNAVAILABLE'),
        cameraStatus: PermissionStatus.granted,
      );

      expect(failure.allowRetry, isFalse);
      expect(failure.allowCameraFallback, isTrue);
      expect(failure.allowGalleryFallback, isTrue);
      expect(failure.message, contains('not available'));
    });

    test('offers retry and fallbacks when scanner launch times out', () {
      final failure = coverCaptureFailureFor(
        error: TimeoutException('timed out'),
        cameraStatus: PermissionStatus.granted,
      );

      expect(failure.allowRetry, isTrue);
      expect(failure.allowCameraFallback, isTrue);
      expect(failure.allowGalleryFallback, isTrue);
      expect(failure.message, contains('too long'));
    });
  });

  group('fullImageCoverCropRect', () {
    test('uses the full scanned image as the initial crop rectangle', () {
      const viewport = Rect.fromLTWH(0, 0, 390, 640);
      const image = Rect.fromLTWH(24, 0, 342, 640);

      expect(fullImageCoverCropRect(viewport, image), image);
    });
  });
}
