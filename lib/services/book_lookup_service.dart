import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/models/book_model.dart';
import 'llll_book_database.dart';

/// Resolves ISBN codes to full book metadata using a fallback chain:
/// Local LLLL database → Firestore cache → Google Books API → Open Library API → null
class BookLookupService {
  BookLookupService({
    FirebaseFirestore? firestore,
    http.Client? httpClient,
    String? googleBooksApiKey,
    LlllBookDatabase? llllDatabase,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _httpClient = httpClient ?? http.Client(),
        _googleBooksApiKey = googleBooksApiKey ??
            const String.fromEnvironment('GOOGLE_BOOKS_API_KEY'),
        _llllDatabase = llllDatabase ?? LlllBookDatabase();

  final FirebaseFirestore _firestore;
  final http.Client _httpClient;
  final String _googleBooksApiKey;
  final LlllBookDatabase _llllDatabase;

  static const _httpTimeout = Duration(seconds: 5);

  /// Access the local LLLL book database for direct queries.
  LlllBookDatabase get llllDatabase => _llllDatabase;

  /// Ensure the local LLLL database is loaded. Call at app startup.
  Future<void> loadLocalDatabase() => _llllDatabase.load();

  /// Look up a book by ISBN. Returns a [BookModel] if found, null otherwise.
  /// Checks local LLLL database first, then Firestore cache, then external APIs.
  /// Results from APIs are cached to Firestore for future lookups.
  Future<BookModel?> lookupByIsbn({
    required String isbn,
    required String schoolId,
    required String actorId,
  }) async {
    // 0. Local LLLL database (instant, no network)
    if (_llllDatabase.isLoaded) {
      final llllResult = _llllDatabase.lookupByIsbn(isbn);
      if (llllResult != null) {
        return _llllDatabase.toBookModel(llllResult);
      }
    }

    // 1. Firestore cache
    final cached = await _lookupInFirestore(isbn);
    if (cached != null && cached.metadata?['placeholder'] != true) {
      return cached;
    }

    // 2. Google Books API
    final googleResult = await _fetchFromGoogleBooks(isbn);
    if (googleResult != null) {
      await _cacheBookInFirestore(
        isbn: isbn,
        book: googleResult,
        source: 'google_books',
        schoolId: schoolId,
        actorId: actorId,
      );
      return googleResult;
    }

    // 3. Open Library API
    final openLibResult = await _fetchFromOpenLibrary(isbn);
    if (openLibResult != null) {
      await _cacheBookInFirestore(
        isbn: isbn,
        book: openLibResult,
        source: 'open_library',
        schoolId: schoolId,
        actorId: actorId,
      );
      return openLibResult;
    }

    // 4. Return existing placeholder if we had one, otherwise null
    return cached;
  }

  /// Look up a book by title search. Returns a [BookModel] if found, null otherwise.
  /// Uses Google Books and Open Library search APIs with title-based queries.
  /// Results are cached to Firestore keyed by normalized title.
  Future<BookModel?> lookupByTitle({
    required String title,
    required String schoolId,
    required String actorId,
  }) async {
    final normalized = normalizeTitle(title);
    if (normalized.isEmpty) return null;

    // 0. Local LLLL database title search
    if (_llllDatabase.isLoaded) {
      final llllResults = _llllDatabase.searchByTitle(title, limit: 1);
      if (llllResults.isNotEmpty) {
        return _llllDatabase.toBookModel(llllResults.first);
      }
    }

    // 1. Firestore cache by normalized title
    final cached = await _lookupByTitleInFirestore(normalized);
    if (cached != null) {
      // If it's a "not found" placeholder, check TTL (re-search after 7 days)
      final searchedAt = cached.metadata?['lastSearchedAt'];
      if (cached.metadata?['titleNotFound'] == true && searchedAt is Timestamp) {
        final daysSinceSearch =
            DateTime.now().difference(searchedAt.toDate()).inDays;
        if (daysSinceSearch < 7) return null; // Still within TTL
        // TTL expired — fall through to re-search
      } else {
        return cached;
      }
    }

    // 2. Google Books title search
    final googleResult = await _fetchFromGoogleBooksByTitle(title);
    if (googleResult != null) {
      await _cacheBookByTitle(
        normalizedTitle: normalized,
        book: googleResult,
        source: 'google_books',
        schoolId: schoolId,
        actorId: actorId,
      );
      return googleResult;
    }

    // 3. Open Library title search
    final openLibResult = await _fetchFromOpenLibraryByTitle(title);
    if (openLibResult != null) {
      await _cacheBookByTitle(
        normalizedTitle: normalized,
        book: openLibResult,
        source: 'open_library',
        schoolId: schoolId,
        actorId: actorId,
      );
      return openLibResult;
    }

    // 4. Cache a "not found" marker so we don't re-search immediately
    await _cacheNotFoundByTitle(
      normalizedTitle: normalized,
      originalTitle: title,
      schoolId: schoolId,
      actorId: actorId,
    );
    return null;
  }

  /// Normalize a title for cache keying: lowercase, trimmed, collapsed whitespace.
  static String normalizeTitle(String title) {
    return title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Resolve all placeholder books in Firestore that were created before
  /// API integration was available.
  Future<int> resolveAllPlaceholders({required String schoolId}) async {
    final query = await _firestore
        .collection('books')
        .where('metadata.placeholder', isEqualTo: true)
        .get();

    var resolved = 0;
    for (final doc in query.docs) {
      final data = doc.data();
      final isbn = data['isbnNormalized'] as String? ?? data['isbn'] as String?;
      if (isbn == null || isbn.isEmpty) continue;

      // Try local LLLL database first
      if (_llllDatabase.isLoaded) {
        final llllResult = _llllDatabase.lookupByIsbn(isbn);
        if (llllResult != null) {
          final book = _llllDatabase.toBookModel(llllResult);
          await _cacheBookInFirestore(
            isbn: isbn,
            book: book,
            source: 'llll_local_db',
            schoolId: schoolId,
            actorId: 'system',
          );
          resolved++;
          continue;
        }
      }

      final book = await _fetchFromGoogleBooks(isbn) ??
          await _fetchFromOpenLibrary(isbn);
      if (book != null) {
        await _cacheBookInFirestore(
          isbn: isbn,
          book: book,
          source: book.metadata?['source'] as String? ?? 'api',
          schoolId: schoolId,
          actorId: 'system',
        );
        resolved++;
      }
    }
    return resolved;
  }

  // ─── Firestore lookup ────────────────────────────────────

  Future<BookModel?> _lookupInFirestore(String isbn) async {
    try {
      final byNormalized = await _firestore
          .collection('books')
          .where('isbnNormalized', isEqualTo: isbn)
          .limit(1)
          .get();

      if (byNormalized.docs.isNotEmpty) {
        return BookModel.fromFirestore(byNormalized.docs.first);
      }

      final byRaw = await _firestore
          .collection('books')
          .where('isbn', isEqualTo: isbn)
          .limit(1)
          .get();

      if (byRaw.docs.isNotEmpty) {
        return BookModel.fromFirestore(byRaw.docs.first);
      }
    } catch (e) {
      debugPrint('BookLookupService: Firestore lookup failed: $e');
    }
    return null;
  }

  // ─── Google Books API ────────────────────────────────────

  Future<BookModel?> _fetchFromGoogleBooks(String isbn) async {
    try {
      final uri = Uri.parse(
        'https://www.googleapis.com/books/v1/volumes'
        '?q=isbn:$isbn'
        '${_googleBooksApiKey.isNotEmpty ? '&key=$_googleBooksApiKey' : ''}',
      );

      final response = await _httpClient.get(uri).timeout(_httpTimeout);
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final totalItems = json['totalItems'] as int? ?? 0;
      if (totalItems == 0) return null;

      final items = json['items'] as List<dynamic>?;
      if (items == null || items.isEmpty) return null;

      final volumeInfo =
          (items[0] as Map<String, dynamic>)['volumeInfo'] as Map<String, dynamic>?;
      if (volumeInfo == null) return null;

      final googleId = (items[0] as Map<String, dynamic>)['id'] as String?;

      // Extract cover URL and ensure HTTPS
      String? coverUrl;
      final imageLinks = volumeInfo['imageLinks'] as Map<String, dynamic>?;
      if (imageLinks != null) {
        coverUrl = (imageLinks['thumbnail'] as String?) ??
            (imageLinks['smallThumbnail'] as String?);
        if (coverUrl != null) {
          coverUrl = coverUrl.replaceFirst('http://', 'https://');
        }
      }

      final authors = volumeInfo['authors'] as List<dynamic>?;
      final categories = volumeInfo['categories'] as List<dynamic>?;

      return BookModel(
        id: 'isbn_$isbn',
        title: volumeInfo['title'] as String? ?? 'Unknown Title',
        author: authors?.isNotEmpty == true ? authors!.first as String : null,
        isbn: isbn,
        coverImageUrl: coverUrl,
        description: volumeInfo['description'] as String?,
        genres: categories?.map((c) => c.toString()).toList() ?? const [],
        pageCount: volumeInfo['pageCount'] as int?,
        publisher: volumeInfo['publisher'] as String?,
        publishedDate: _parsePublishedDate(
            volumeInfo['publishedDate'] as String?),
        createdAt: DateTime.now(),
        metadata: {
          'source': 'google_books',
          'googleBooksId': googleId,
          'resolvedAt': Timestamp.fromDate(DateTime.now()),
        },
      );
    } catch (e) {
      debugPrint('BookLookupService: Google Books lookup failed: $e');
      return null;
    }
  }

  // ─── Open Library API ────────────────────────────────────

  Future<BookModel?> _fetchFromOpenLibrary(String isbn) async {
    try {
      // Use the search API which returns author names directly
      final uri = Uri.parse(
        'https://openlibrary.org/search.json?isbn=$isbn&fields=title,author_name,publisher,number_of_pages_median,first_publish_year,subject&limit=1',
      );

      final response = await _httpClient.get(uri).timeout(_httpTimeout);
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final numFound = json['numFound'] as int? ?? 0;
      if (numFound == 0) return null;

      final docs = json['docs'] as List<dynamic>?;
      if (docs == null || docs.isEmpty) return null;

      final doc = docs[0] as Map<String, dynamic>;
      final title = doc['title'] as String?;
      if (title == null || title.isEmpty) return null;

      final authorNames = doc['author_name'] as List<dynamic>?;
      final publishers = doc['publisher'] as List<dynamic>?;
      final subjects = doc['subject'] as List<dynamic>?;
      final pageCount = doc['number_of_pages_median'] as int?;

      // Open Library provides predictable cover URLs by ISBN
      final coverUrl = 'https://covers.openlibrary.org/b/isbn/$isbn-M.jpg';

      DateTime? publishedDate;
      final firstYear = doc['first_publish_year'] as int?;
      if (firstYear != null) {
        publishedDate = DateTime(firstYear);
      }

      return BookModel(
        id: 'isbn_$isbn',
        title: title,
        author: authorNames?.isNotEmpty == true
            ? authorNames!.first.toString()
            : null,
        isbn: isbn,
        coverImageUrl: coverUrl,
        genres: subjects
                ?.take(5)
                .map((s) => s.toString())
                .toList() ??
            const [],
        pageCount: pageCount,
        publisher: publishers?.isNotEmpty == true
            ? publishers!.first.toString()
            : null,
        publishedDate: publishedDate,
        createdAt: DateTime.now(),
        metadata: {
          'source': 'open_library',
          'resolvedAt': Timestamp.fromDate(DateTime.now()),
        },
      );
    } catch (e) {
      debugPrint('BookLookupService: Open Library lookup failed: $e');
      return null;
    }
  }

  // ─── Firestore cache write ───────────────────────────────

  Future<void> _cacheBookInFirestore({
    required String isbn,
    required BookModel book,
    required String source,
    required String schoolId,
    required String actorId,
  }) async {
    try {
      final ref = _firestore.collection('books').doc('isbn_$isbn');
      final now = DateTime.now();

      await ref.set(
        {
          'title': book.title,
          'author': book.author,
          'isbn': isbn,
          'isbnNormalized': isbn,
          'coverImageUrl': book.coverImageUrl,
          'description': book.description,
          'genres': book.genres,
          'pageCount': book.pageCount,
          'publisher': book.publisher,
          'publishedDate': book.publishedDate != null
              ? Timestamp.fromDate(book.publishedDate!)
              : null,
          'tags': <String>[],
          'schoolId': schoolId,
          'addedBy': actorId,
          'createdAt': Timestamp.fromDate(now),
          'metadata': {
            'source': source,
            'placeholder': false,
            'resolvedAt': Timestamp.fromDate(now),
            if (book.metadata?['googleBooksId'] != null)
              'googleBooksId': book.metadata!['googleBooksId'],
          },
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('BookLookupService: Cache write failed: $e');
    }
  }

  // ─── Title-based Firestore lookup ───────────────────────

  Future<BookModel?> _lookupByTitleInFirestore(String normalizedTitle) async {
    try {
      final query = await _firestore
          .collection('books')
          .where('titleNormalized', isEqualTo: normalizedTitle)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        return BookModel.fromFirestore(query.docs.first);
      }
    } catch (e) {
      debugPrint('BookLookupService: Title Firestore lookup failed: $e');
    }
    return null;
  }

  // ─── Google Books title search ─────────────────────────

  Future<BookModel?> _fetchFromGoogleBooksByTitle(String title) async {
    try {
      final encoded = Uri.encodeComponent(title);
      final uri = Uri.parse(
        'https://www.googleapis.com/books/v1/volumes'
        '?q=intitle:$encoded&maxResults=1'
        '${_googleBooksApiKey.isNotEmpty ? '&key=$_googleBooksApiKey' : ''}',
      );

      final response = await _httpClient.get(uri).timeout(_httpTimeout);
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final totalItems = json['totalItems'] as int? ?? 0;
      if (totalItems == 0) return null;

      final items = json['items'] as List<dynamic>?;
      if (items == null || items.isEmpty) return null;

      final volumeInfo =
          (items[0] as Map<String, dynamic>)['volumeInfo'] as Map<String, dynamic>?;
      if (volumeInfo == null) return null;

      final googleId = (items[0] as Map<String, dynamic>)['id'] as String?;

      String? coverUrl;
      final imageLinks = volumeInfo['imageLinks'] as Map<String, dynamic>?;
      if (imageLinks != null) {
        coverUrl = (imageLinks['thumbnail'] as String?) ??
            (imageLinks['smallThumbnail'] as String?);
        if (coverUrl != null) {
          coverUrl = coverUrl.replaceFirst('http://', 'https://');
        }
      }

      final authors = volumeInfo['authors'] as List<dynamic>?;
      final categories = volumeInfo['categories'] as List<dynamic>?;

      // Extract ISBN if available
      String? isbn;
      final identifiers =
          volumeInfo['industryIdentifiers'] as List<dynamic>?;
      if (identifiers != null) {
        for (final id in identifiers) {
          final idMap = id as Map<String, dynamic>;
          if (idMap['type'] == 'ISBN_13') {
            isbn = idMap['identifier'] as String?;
            break;
          } else if (idMap['type'] == 'ISBN_10' && isbn == null) {
            isbn = idMap['identifier'] as String?;
          }
        }
      }

      return BookModel(
        id: isbn != null ? 'isbn_$isbn' : 'title_${normalizeTitle(title)}',
        title: volumeInfo['title'] as String? ?? title,
        author: authors?.isNotEmpty == true ? authors!.first as String : null,
        isbn: isbn,
        coverImageUrl: coverUrl,
        description: volumeInfo['description'] as String?,
        genres: categories?.map((c) => c.toString()).toList() ?? const [],
        pageCount: volumeInfo['pageCount'] as int?,
        publisher: volumeInfo['publisher'] as String?,
        publishedDate:
            _parsePublishedDate(volumeInfo['publishedDate'] as String?),
        createdAt: DateTime.now(),
        metadata: {
          'source': 'google_books',
          'googleBooksId': googleId,
          'resolvedAt': Timestamp.fromDate(DateTime.now()),
        },
      );
    } catch (e) {
      debugPrint('BookLookupService: Google Books title search failed: $e');
      return null;
    }
  }

  // ─── Open Library title search ─────────────────────────

  Future<BookModel?> _fetchFromOpenLibraryByTitle(String title) async {
    try {
      final encoded = Uri.encodeComponent(title);
      final uri = Uri.parse(
        'https://openlibrary.org/search.json'
        '?title=$encoded'
        '&fields=title,author_name,publisher,number_of_pages_median,first_publish_year,subject,isbn,cover_i'
        '&limit=1',
      );

      final response = await _httpClient.get(uri).timeout(_httpTimeout);
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final numFound = json['numFound'] as int? ?? 0;
      if (numFound == 0) return null;

      final docs = json['docs'] as List<dynamic>?;
      if (docs == null || docs.isEmpty) return null;

      final doc = docs[0] as Map<String, dynamic>;
      final resultTitle = doc['title'] as String?;
      if (resultTitle == null || resultTitle.isEmpty) return null;

      final authorNames = doc['author_name'] as List<dynamic>?;
      final publishers = doc['publisher'] as List<dynamic>?;
      final subjects = doc['subject'] as List<dynamic>?;
      final pageCount = doc['number_of_pages_median'] as int?;
      final coverId = doc['cover_i'] as int?;

      // Try to get ISBN for cover URL
      String? isbn;
      final isbns = doc['isbn'] as List<dynamic>?;
      if (isbns != null && isbns.isNotEmpty) {
        // Prefer ISBN-13
        isbn = isbns.firstWhere(
          (i) => i.toString().length == 13,
          orElse: () => isbns.first,
        ).toString();
      }

      // Build cover URL: prefer ISBN-based, fallback to cover ID
      String? coverUrl;
      if (isbn != null) {
        coverUrl = 'https://covers.openlibrary.org/b/isbn/$isbn-M.jpg';
      } else if (coverId != null) {
        coverUrl = 'https://covers.openlibrary.org/b/id/$coverId-M.jpg';
      }

      DateTime? publishedDate;
      final firstYear = doc['first_publish_year'] as int?;
      if (firstYear != null) {
        publishedDate = DateTime(firstYear);
      }

      return BookModel(
        id: isbn != null ? 'isbn_$isbn' : 'title_${normalizeTitle(title)}',
        title: resultTitle,
        author: authorNames?.isNotEmpty == true
            ? authorNames!.first.toString()
            : null,
        isbn: isbn,
        coverImageUrl: coverUrl,
        genres:
            subjects?.take(5).map((s) => s.toString()).toList() ?? const [],
        pageCount: pageCount,
        publisher: publishers?.isNotEmpty == true
            ? publishers!.first.toString()
            : null,
        publishedDate: publishedDate,
        createdAt: DateTime.now(),
        metadata: {
          'source': 'open_library',
          'resolvedAt': Timestamp.fromDate(DateTime.now()),
        },
      );
    } catch (e) {
      debugPrint('BookLookupService: Open Library title search failed: $e');
      return null;
    }
  }

  // ─── Title-based cache writes ──────────────────────────

  Future<void> _cacheBookByTitle({
    required String normalizedTitle,
    required BookModel book,
    required String source,
    required String schoolId,
    required String actorId,
  }) async {
    try {
      final ref = _firestore.collection('books').doc(book.id);
      final now = DateTime.now();

      await ref.set(
        {
          'title': book.title,
          'titleNormalized': normalizedTitle,
          'author': book.author,
          'isbn': book.isbn,
          'isbnNormalized': book.isbn,
          'coverImageUrl': book.coverImageUrl,
          'description': book.description,
          'genres': book.genres,
          'pageCount': book.pageCount,
          'publisher': book.publisher,
          'publishedDate': book.publishedDate != null
              ? Timestamp.fromDate(book.publishedDate!)
              : null,
          'tags': <String>[],
          'schoolId': schoolId,
          'addedBy': actorId,
          'createdAt': Timestamp.fromDate(now),
          'metadata': {
            'source': source,
            'placeholder': false,
            'resolvedAt': Timestamp.fromDate(now),
            if (book.metadata?['googleBooksId'] != null)
              'googleBooksId': book.metadata!['googleBooksId'],
          },
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('BookLookupService: Title cache write failed: $e');
    }
  }

  Future<void> _cacheNotFoundByTitle({
    required String normalizedTitle,
    required String originalTitle,
    required String schoolId,
    required String actorId,
  }) async {
    try {
      final ref =
          _firestore.collection('books').doc('title_$normalizedTitle');
      final now = DateTime.now();

      await ref.set(
        {
          'title': originalTitle,
          'titleNormalized': normalizedTitle,
          'schoolId': schoolId,
          'addedBy': actorId,
          'createdAt': Timestamp.fromDate(now),
          'metadata': {
            'placeholder': true,
            'titleNotFound': true,
            'lastSearchedAt': Timestamp.fromDate(now),
          },
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('BookLookupService: Not-found cache write failed: $e');
    }
  }

  // ─── Helpers ─────────────────────────────────────────────

  static DateTime? _parsePublishedDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    try {
      // Google Books returns "2024-03-15", "2024-03", or "2024"
      final parts = dateStr.split('-');
      return DateTime(
        int.parse(parts[0]),
        parts.length > 1 ? int.parse(parts[1]) : 1,
        parts.length > 2 ? int.parse(parts[2]) : 1,
      );
    } catch (_) {
      return null;
    }
  }
}
