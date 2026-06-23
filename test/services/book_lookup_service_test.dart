import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumi_reading_tracker/services/book_lookup_service.dart';

/// Exercises the Google Books → Open Library fallback rules in
/// [BookLookupService.lookupByIsbn], driven entirely through stubbed HTTP so no
/// network is hit. `schoolId: ''` disables the Firestore cache layer, isolating
/// the API/adapter logic. The injected [FakeFirebaseFirestore] is empty, so the
/// unconditional community-books lookup simply misses.
void main() {
  // A valid ISBN-13 (Harry Potter) — passes the checksum so it is not mangled
  // by the service's ISBN normalisation.
  const isbn = '9780439708180';

  http.Response json(Object body) => http.Response(jsonEncode(body), 200);

  /// Builds a service whose HTTP client routes by host/path to the supplied
  /// stub responses.
  BookLookupService buildService({
    required Map<String, dynamic> googleResponse,
    Map<String, dynamic>? openLibrarySearchResponse,
    Map<String, dynamic>? openLibraryWorkResponse,
  }) {
    final client = MockClient((request) async {
      final url = request.url;
      if (url.host == 'www.googleapis.com') {
        return json(googleResponse);
      }
      if (url.host == 'openlibrary.org' && url.path == '/search.json') {
        return json(openLibrarySearchResponse ?? {'numFound': 0, 'docs': []});
      }
      if (url.host == 'openlibrary.org' && url.path.startsWith('/works/')) {
        return json(openLibraryWorkResponse ?? <String, dynamic>{});
      }
      return http.Response('not found', 404);
    });

    return BookLookupService(
      firestore: FakeFirebaseFirestore(),
      httpClient: client,
      googleBooksApiKey: '',
    );
  }

  Future<dynamic> lookup(BookLookupService service) => service.lookupByIsbn(
        isbn: isbn,
        schoolId: '',
        actorId: 'tester',
      );

  group('BookLookupService partial-match fallback', () {
    test('fills a missing Google cover from Open Library cover_i', () async {
      final service = buildService(
        googleResponse: {
          'totalItems': 1,
          'items': [
            {
              'id': 'GID',
              'volumeInfo': {
                'title': 'Test Book',
                'authors': ['Jane Doe'],
                'description': 'Google has a description.',
                // no imageLinks → cover is missing
              },
            },
          ],
        },
        openLibrarySearchResponse: {
          'numFound': 1,
          'docs': [
            {'key': '/works/OL1W', 'title': 'Test Book', 'cover_i': 12345},
          ],
        },
      );

      final result = await lookup(service);

      expect(result, isNotNull);
      expect(result!.coverImageUrl,
          'https://covers.openlibrary.org/b/id/12345-M.jpg');
      expect(result.metadata?['coverSource'], 'open_library');
      // Google's description is intact, so no OL description fill happened.
      expect(result.description, 'Google has a description.');
    });

    test('leaves cover null when Open Library has no cover_i (no phantom)',
        () async {
      final service = buildService(
        googleResponse: {
          'totalItems': 1,
          'items': [
            {
              'id': 'GID',
              'volumeInfo': {
                'title': 'Test Book',
                'authors': ['Jane Doe'],
                'description': 'Google has a description.',
              },
            },
          ],
        },
        openLibrarySearchResponse: {
          'numFound': 1,
          'docs': [
            {'key': '/works/OL1W', 'title': 'Test Book'}, // no cover_i
          ],
        },
      );

      final result = await lookup(service);

      expect(result, isNotNull);
      expect(result!.coverImageUrl, isNull);
      expect(result.metadata?['coverSource'], isNull);
    });

    test('fills a blank Google description from the Open Library Work',
        () async {
      final service = buildService(
        googleResponse: {
          'totalItems': 1,
          'items': [
            {
              'id': 'GID',
              'volumeInfo': {
                'title': 'Test Book',
                'authors': ['Jane Doe'],
                'imageLinks': {'thumbnail': 'http://books.google/cover.jpg'},
                // no description → description is missing
              },
            },
          ],
        },
        openLibrarySearchResponse: {
          'numFound': 1,
          'docs': [
            {'key': '/works/OL1W', 'title': 'Test Book', 'cover_i': 999},
          ],
        },
        openLibraryWorkResponse: {'description': 'Synopsis from Open Library.'},
      );

      final result = await lookup(service);

      expect(result, isNotNull);
      expect(result!.description, 'Synopsis from Open Library.');
      expect(result.metadata?['descriptionSource'], 'open_library');
      // Google cover is kept and upgraded to https.
      expect(result.coverImageUrl, 'https://books.google/cover.jpg');
    });
  });

  group('BookLookupService Open Library-only path', () {
    test('returns an enriched model (cover, genres, date, description)',
        () async {
      final service = buildService(
        googleResponse: {'totalItems': 0},
        openLibrarySearchResponse: {
          'numFound': 1,
          'docs': [
            {
              'key': '/works/OL2W',
              'title': 'OL Only Book',
              'author_name': ['John Smith'],
              'subject': ['Fiction', 'Adventure'],
              'first_publish_year': 2001,
              'number_of_pages_median': 120,
              'cover_i': 555,
            },
          ],
        },
        // Object form: {type, value}
        openLibraryWorkResponse: {
          'description': {
            'type': '/type/text',
            'value': 'OL only description.',
          },
        },
      );

      final result = await lookup(service);

      expect(result, isNotNull);
      expect(result!.title, 'OL Only Book');
      expect(result.author, 'John Smith');
      expect(result.genres, contains('Fiction'));
      expect(result.publishedDate?.year, 2001);
      expect(result.pageCount, 120);
      expect(
          result.coverImageUrl, 'https://covers.openlibrary.org/b/id/555-M.jpg');
      expect(result.description, 'OL only description.');
      expect(result.metadata?['source'], 'open_library');
    });
  });
}
