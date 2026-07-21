import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/screens/teacher/cover_scanner_screen.dart';
import 'package:lumi_reading_tracker/services/book_cover_ocr_service.dart';
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

  group('useSinglePhotoCoverCapture', () {
    test('uses a one-image camera flow for iOS book covers', () {
      expect(
        useSinglePhotoCoverCapture(TargetPlatform.iOS),
        isTrue,
      );
      expect(
        useSinglePhotoCoverCapture(TargetPlatform.android),
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

  group('bookMetadataLookupNotice', () {
    test('points at the form when every catalog is unreachable', () {
      // Wording is "check the details" rather than "enter them manually":
      // cover OCR may have already filled the fields by the time this shows.
      expect(
        bookMetadataLookupNotice(
          bookResolved: false,
          lookupUnavailable: true,
        ),
        contains('Check the details'),
      );
    });

    test('does not show an outage notice for a genuine miss or a result', () {
      expect(
        bookMetadataLookupNotice(
          bookResolved: false,
          lookupUnavailable: false,
        ),
        isNull,
      );
      expect(
        bookMetadataLookupNotice(
          bookResolved: true,
          lookupUnavailable: true,
        ),
        isNull,
      );
    });
  });

  group('unresolvedBookPromptMessage', () {
    test('explains why a genuine miss opens the cover scanner', () {
      final message = unresolvedBookPromptMessage(
        isbn: '9799999900019',
        catalogUnavailable: false,
      );

      expect(message, contains('was not found'));
      expect(message, contains('Lumi library'));
      expect(message, contains('scanning the front cover'));
      expect(message, contains('checking the book details'));
    });

    test('does not mislabel a catalogue outage as a definite miss', () {
      final message = unresolvedBookPromptMessage(
        isbn: '9799999900019',
        catalogUnavailable: true,
      );

      expect(message, contains('could not reach'));
      expect(message, isNot(contains('was not found')));
      expect(message, contains('still add'));
    });
  });

  group('fullImageCoverCropRect', () {
    test('uses the full scanned image as the initial crop rectangle', () {
      const viewport = Rect.fromLTWH(0, 0, 390, 640);
      const image = Rect.fromLTWH(24, 0, 342, 640);

      expect(fullImageCoverCropRect(viewport, image), image);
    });
  });

  group('ocrFieldUpdates', () {
    ({String? title, String? author}) updates({
      String ocrTitle = 'The Gruffalo',
      double titleConfidence = 0.95,
      String ocrAuthor = 'Julia Donaldson',
      double authorConfidence = 0.9,
      String currentTitle = '',
      String currentAuthor = '',
    }) {
      return ocrFieldUpdates(
        ocrTitle: ocrTitle,
        titleConfidence: titleConfidence,
        ocrAuthor: ocrAuthor,
        authorConfidence: authorConfidence,
        currentTitle: currentTitle,
        currentAuthor: currentAuthor,
      );
    }

    test('fills both fields when the model is confident and both are empty',
        () {
      final result = updates();
      expect(result.title, 'The Gruffalo');
      expect(result.author, 'Julia Donaldson');
    });

    test('fills only the field that clears the threshold', () {
      // The expected everyday outcome: a title is large display text and
      // reads reliably, an author name is small and stylised and often
      // does not.
      final result = updates(authorConfidence: 0.41);
      expect(result.title, 'The Gruffalo');
      expect(result.author, isNull);
    });

    test('treats the threshold as inclusive', () {
      final result = updates(
        titleConfidence: kOcrConfidenceThreshold,
        authorConfidence: kOcrConfidenceThreshold - 0.01,
      );
      expect(result.title, isNotNull);
      expect(result.author, isNull);
    });

    test('never overwrites a value that is already present', () {
      // Catalog data is authoritative. In standalone mode the lookup has
      // already run before the cover is captured; inline mode runs it
      // after. Guarding on "is it empty" makes both orderings identical.
      final result = updates(
        currentTitle: 'Catalogue Title',
        currentAuthor: 'Catalogue Author',
      );
      expect(result.title, isNull);
      expect(result.author, isNull);
    });

    test('treats a whitespace-only field as empty and fills it', () {
      final result = updates(currentTitle: '   ');
      expect(result.title, 'The Gruffalo');
    });

    test('never fills from a blank suggestion, whatever the confidence', () {
      final result = updates(
        ocrTitle: '',
        titleConfidence: 1,
        ocrAuthor: '   ',
        authorConfidence: 1,
      );
      expect(result.title, isNull);
      expect(result.author, isNull);
    });

    test('trims the value it writes', () {
      final result = updates(ocrTitle: '  Zog  ', ocrAuthor: ' A. Author ');
      expect(result.title, 'Zog');
      expect(result.author, 'A. Author');
    });

    test('a retaken cover can replace a value the previous read filled', () {
      // Regression: _retakeCover must clear OCR-sourced values first. If a
      // stale suggestion is still in the controller, the empty-field guard
      // below rejects the fresh read — so retaking the photo, the one action
      // a teacher takes to fix a bad read, would silently do nothing.
      final blocked = updates(
        ocrTitle: 'Corrected Title',
        currentTitle: 'Wrong Title From Old Cover',
      );
      expect(blocked.title, isNull);

      // ...which is why the retake path clears it, giving this instead:
      final afterRetakeClears = updates(
        ocrTitle: 'Corrected Title',
        currentTitle: '',
      );
      expect(afterRetakeClears.title, 'Corrected Title');
    });

    test('zero confidence never fills — the failure default', () {
      // The service returns empty/0 for every failure path (offline, kill
      // switch off, provider outage), so this is what "degrade silently"
      // actually resolves to.
      final result = updates(titleConfidence: 0, authorConfidence: 0);
      expect(result.title, isNull);
      expect(result.author, isNull);
    });
  });

  group('CoverOcrSuggestion.fromMap', () {
    test('reads a well-formed callable response', () {
      final suggestion = CoverOcrSuggestion.fromMap(const {
        'title': 'The Gruffalo',
        'titleConfidence': 0.94,
        'author': 'Julia Donaldson',
        'authorConfidence': 0.88,
        'model': 'gemini-2.5-flash',
      });
      expect(suggestion.title, 'The Gruffalo');
      expect(suggestion.titleConfidence, 0.94);
      expect(suggestion.author, 'Julia Donaldson');
      expect(suggestion.model, 'gemini-2.5-flash');
      expect(suggestion.isEmpty, isFalse);
    });

    test('clamps and defaults hostile or missing values', () {
      final suggestion = CoverOcrSuggestion.fromMap(const {
        'title': 'A',
        'titleConfidence': 7,
        'authorConfidence': 'high',
      });
      expect(suggestion.titleConfidence, 1);
      expect(suggestion.author, '');
      expect(suggestion.authorConfidence, 0);
      expect(suggestion.model, '');
    });

    test('an int confidence from the wire is read as a double', () {
      // Callable JSON gives back num; 1 and 0 arrive as int, not double.
      final suggestion = CoverOcrSuggestion.fromMap(const {
        'title': 'A',
        'titleConfidence': 1,
      });
      expect(suggestion.titleConfidence, 1.0);
    });

    test('the disabled/failed response reads as empty', () {
      final suggestion = CoverOcrSuggestion.fromMap(const {
        'title': '',
        'titleConfidence': 0,
        'author': '',
        'authorConfidence': 0,
        'disabled': true,
      });
      expect(suggestion.isEmpty, isTrue);
    });
  });
}
