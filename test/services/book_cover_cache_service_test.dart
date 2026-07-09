import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/services/book_cover_cache_service.dart';

void main() {
  group('BookCoverCacheService', () {
    test('detects optimistic Open Library ISBN fallback URLs', () {
      expect(
        BookCoverCacheService.isFallbackCoverUrl(
          'https://covers.openlibrary.org/b/isbn/9780000000002-M.jpg?default=false',
        ),
        isTrue,
      );
      expect(
        BookCoverCacheService.isFallbackCoverUrl(
          'https://covers.openlibrary.org/b/id/555-M.jpg',
        ),
        isFalse,
      );
      expect(
        BookCoverCacheService.isFallbackCoverUrl(
          'https://firebasestorage.googleapis.com/v0/b/lumi/o/community_books%2Fcovers%2F9780000000002.jpg',
        ),
        isFalse,
      );
    });

    test('lets a real uploaded cover replace a fallback but not the reverse',
        () {
      const isbn = '9780000000095';
      const title = 'Fallback Replacement Test';
      const uploadedCover =
          'https://firebasestorage.googleapis.com/v0/b/lumi/o/community_books%2Fcovers%2F9780000000095.jpg';
      final service = BookCoverCacheService.instance;

      service.cacheFromIsbnLookup(
        isbn: isbn,
        title: title,
        coverImageUrl: null,
      );
      expect(
        BookCoverCacheService.isFallbackCoverUrl(
          service.resolveCoverUrlByIsbn(isbn),
        ),
        isTrue,
      );

      service.cacheFromIsbnLookup(
        isbn: isbn,
        title: title,
        coverImageUrl: uploadedCover,
      );
      expect(service.resolveCoverUrlByIsbn(isbn), uploadedCover);

      service.cacheFromIsbnLookup(
        isbn: isbn,
        title: title,
        coverImageUrl: null,
      );
      expect(service.resolveCoverUrlByIsbn(isbn), uploadedCover);
    });
  });
}
