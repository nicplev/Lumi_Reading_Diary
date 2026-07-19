import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/screens/teacher/student_detail/assigned_books_section.dart';

void main() {
  group('shouldHydrateStudentDetailIsbnCover', () {
    test('treats missing and fallback covers as unresolved', () {
      expect(shouldHydrateStudentDetailIsbnCover(null), isTrue);
      expect(shouldHydrateStudentDetailIsbnCover(''), isTrue);
      expect(
        shouldHydrateStudentDetailIsbnCover(
          'https://covers.openlibrary.org/b/isbn/9780000000002-M.jpg?default=false',
        ),
        isTrue,
      );
    });

    test('treats real API and uploaded covers as resolved', () {
      expect(
        shouldHydrateStudentDetailIsbnCover(
          'https://covers.openlibrary.org/b/id/555-M.jpg',
        ),
        isFalse,
      );
      expect(
        shouldHydrateStudentDetailIsbnCover(
          'https://firebasestorage.googleapis.com/v0/b/lumi/o/community_books%2Fcovers%2F9780000000002.jpg',
        ),
        isFalse,
      );
    });
  });
}
