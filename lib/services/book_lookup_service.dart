import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/models/book_model.dart';
import 'teacher_device_book_cache_service.dart';

/// Resolves ISBN codes to full book metadata using a fallback chain:
/// Community Books (global) → Firestore cache → Google Books API → Open Library API → null
class BookLookupService {
  BookLookupService({
    FirebaseFirestore? firestore,
    http.Client? httpClient,
    String? googleBooksApiKey,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _httpClient = httpClient ?? http.Client(),
        _googleBooksApiKey = googleBooksApiKey ??
            const String.fromEnvironment('GOOGLE_BOOKS_API_KEY');

  final FirebaseFirestore _firestore;
  final http.Client _httpClient;
  final String _googleBooksApiKey;

  static const _httpTimeout = Duration(seconds: 5);
  bool _firestoreCacheReadEnabled = true;
  bool _firestoreCacheWriteEnabled = true;
  bool _didLogReadPermissionDenial = false;
  bool _didLogWritePermissionDenial = false;

  /// Look up a book by ISBN. Returns a [BookModel] if found, null otherwise.
  /// Checks community books first, then Firestore school cache, then external
  /// APIs. Results from APIs are cached for future lookups.
  Future<BookModel?> lookupByIsbn({
    required String isbn,
    required String schoolId,
    required String actorId,
    bool useFirestoreCache = true,
    bool persistToFirestoreCache = true,
    bool useDeviceScanCache = false,
    bool persistToDeviceScanCache = false,
  }) async {
    final normalizedIsbn = _normalizeIsbnForLookup(isbn);
    if (normalizedIsbn.isEmpty) return null;
    final scopedSchoolId = schoolId.trim();

    // -1. Teacher device cache (instant, no network)
    if (useDeviceScanCache) {
      final deviceCached =
          TeacherDeviceBookCacheService.instance.lookupByIsbn(
        teacherId: actorId,
        schoolId: scopedSchoolId,
        isbn: normalizedIsbn,
      );
      if (deviceCached != null) return deviceCached;
    }

    // 0. Community book database (global, single-document lookup)
    try {
      final communityDoc = await _firestore
          .collection('community_books')
          .doc(normalizedIsbn)
          .get();
      if (communityDoc.exists) {
        final data = communityDoc.data();
        if (data != null &&
            data['title'] != null &&
            (data['title'] as String).isNotEmpty) {
          final result = BookModel.fromFirestore(communityDoc);
          // Write to school library so teachers can browse/search this book
          if (scopedSchoolId.isNotEmpty &&
              persistToFirestoreCache &&
              _firestoreCacheWriteEnabled) {
            await _cacheBookInFirestore(
              isbn: normalizedIsbn,
              book: result,
              source: 'community_books',
              schoolId: scopedSchoolId,
              actorId: actorId,
            );
          }
          if (persistToDeviceScanCache) {
            try {
              await TeacherDeviceBookCacheService.instance.cacheBook(
                teacherId: actorId, schoolId: scopedSchoolId, book: result,
              );
            } catch (_) {}
          }
          return result;
        }
      }
    } catch (e) {
      debugPrint('BookLookupService: Community books lookup failed: $e');
    }

    // 1. Firestore cache
    BookModel? cached;
    if (scopedSchoolId.isNotEmpty &&
        useFirestoreCache &&
        _firestoreCacheReadEnabled) {
      cached = await _lookupInFirestore(
        normalizedIsbn,
        schoolId: scopedSchoolId,
      );
    }
    if (cached != null && cached.metadata?['placeholder'] != true) {
      if (persistToDeviceScanCache) {
        try {
          await TeacherDeviceBookCacheService.instance.cacheBook(
            teacherId: actorId, schoolId: scopedSchoolId, book: cached,
          );
        } catch (_) {}
      }
      return cached;
    }

    // 2. Google Books API
    final googleResult = await _fetchFromGoogleBooks(normalizedIsbn);
    if (googleResult != null) {
      var resolvedResult = googleResult;

      // Google sometimes returns metadata without a thumbnail for valid ISBNs.
      // If so, try Open Library for a deterministic ISBN cover URL.
      if (!_hasUsableCoverUrl(googleResult.coverImageUrl)) {
        final openLibraryFallback = await _fetchFromOpenLibrary(normalizedIsbn);
        if (_hasUsableCoverUrl(openLibraryFallback?.coverImageUrl)) {
          resolvedResult = googleResult.copyWith(
            coverImageUrl: openLibraryFallback!.coverImageUrl,
            metadata: {
              ...?googleResult.metadata,
              'coverSource': 'open_library',
              'resolvedAt': Timestamp.fromDate(DateTime.now()),
            },
          );
        }
      }

      if (scopedSchoolId.isNotEmpty &&
          persistToFirestoreCache &&
          _firestoreCacheWriteEnabled) {
        await _cacheBookInFirestore(
          isbn: normalizedIsbn,
          book: resolvedResult,
          source: resolvedResult.metadata?['coverSource'] == 'open_library'
              ? 'google_books+open_library_cover'
              : 'google_books',
          schoolId: scopedSchoolId,
          actorId: actorId,
        );
      }
      if (persistToDeviceScanCache) {
        try {
          await TeacherDeviceBookCacheService.instance.cacheBook(
            teacherId: actorId, schoolId: scopedSchoolId, book: resolvedResult,
          );
        } catch (_) {}
      }
      return resolvedResult;
    }

    // 3. Open Library API
    final openLibResult = await _fetchFromOpenLibrary(normalizedIsbn);
    if (openLibResult != null) {
      if (scopedSchoolId.isNotEmpty &&
          persistToFirestoreCache &&
          _firestoreCacheWriteEnabled) {
        await _cacheBookInFirestore(
          isbn: normalizedIsbn,
          book: openLibResult,
          source: 'open_library',
          schoolId: scopedSchoolId,
          actorId: actorId,
        );
      }
      if (persistToDeviceScanCache) {
        try {
          await TeacherDeviceBookCacheService.instance.cacheBook(
            teacherId: actorId, schoolId: scopedSchoolId, book: openLibResult,
          );
        } catch (_) {}
      }
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
    bool useFirestoreCache = true,
    bool persistToFirestoreCache = true,
  }) async {
    final normalized = normalizeTitle(title);
    if (normalized.isEmpty) return null;
    final scopedSchoolId = schoolId.trim();

    // 1. Firestore cache by normalized title
    BookModel? cached;
    if (scopedSchoolId.isNotEmpty &&
        useFirestoreCache &&
        _firestoreCacheReadEnabled) {
      cached = await _lookupByTitleInFirestore(
        normalized,
        schoolId: scopedSchoolId,
        originalTitle: title,
      );
    }
    if (cached != null) {
      // If it's a "not found" placeholder, check TTL (re-search after 7 days)
      final searchedAt = cached.metadata?['lastSearchedAt'];
      if (cached.metadata?['titleNotFound'] == true &&
          searchedAt is Timestamp) {
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
      if (scopedSchoolId.isNotEmpty &&
          persistToFirestoreCache &&
          _firestoreCacheWriteEnabled) {
        await _cacheBookByTitle(
          normalizedTitle: normalized,
          book: googleResult,
          source: 'google_books',
          schoolId: scopedSchoolId,
          actorId: actorId,
        );
      }
      return googleResult;
    }

    // 3. Open Library title search
    final openLibResult = await _fetchFromOpenLibraryByTitle(title);
    if (openLibResult != null) {
      if (scopedSchoolId.isNotEmpty &&
          persistToFirestoreCache &&
          _firestoreCacheWriteEnabled) {
        await _cacheBookByTitle(
          normalizedTitle: normalized,
          book: openLibResult,
          source: 'open_library',
          schoolId: scopedSchoolId,
          actorId: actorId,
        );
      }
      return openLibResult;
    }

    // 4. Cache a "not found" marker so we don't re-search immediately
    if (scopedSchoolId.isNotEmpty &&
        persistToFirestoreCache &&
        _firestoreCacheWriteEnabled) {
      await _cacheNotFoundByTitle(
        normalizedTitle: normalized,
        originalTitle: title,
        schoolId: scopedSchoolId,
        actorId: actorId,
      );
    }
    return null;
  }

  /// Normalize a title for cache keying: lowercase, trimmed, collapsed whitespace.
  static String normalizeTitle(String title) {
    return title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  CollectionReference<Map<String, dynamic>> _schoolBooks(String schoolId) {
    return _firestore.collection('schools').doc(schoolId).collection('books');
  }

  CollectionReference<Map<String, dynamic>> get _legacyBooks {
    return _firestore.collection('books');
  }

  /// Resolve all placeholder books in Firestore that were created before
  /// API integration was available.
  Future<int> resolveAllPlaceholders({required String schoolId}) async {
    if (!_firestoreCacheReadEnabled) return 0;
    final scopedSchoolId = schoolId.trim();
    if (scopedSchoolId.isEmpty) return 0;

    QuerySnapshot<Map<String, dynamic>> query;
    try {
      query = await _schoolBooks(scopedSchoolId)
          .where('metadata.placeholder', isEqualTo: true)
          .get();

      if (query.docs.isEmpty) {
        query = await _legacyBooks
            .where('schoolId', isEqualTo: scopedSchoolId)
            .where('metadata.placeholder', isEqualTo: true)
            .get();
      }
    } catch (e) {
      _handleFirestoreReadFailure(e, operation: 'Placeholder query');
      return 0;
    }

    var resolved = 0;
    for (final doc in query.docs) {
      final data = doc.data();
      final isbn = data['isbnNormalized'] as String? ?? data['isbn'] as String?;
      if (isbn == null || isbn.isEmpty) continue;

      final book = await _fetchFromGoogleBooks(isbn) ??
          await _fetchFromOpenLibrary(isbn);
      if (book != null) {
        await _cacheBookInFirestore(
          isbn: isbn,
          book: book,
          source: book.metadata?['source'] as String? ?? 'api',
          schoolId: scopedSchoolId,
          actorId: 'system',
        );
        resolved++;
      }
    }
    return resolved;
  }

  // ─── Firestore lookup ────────────────────────────────────

  Future<BookModel?> _lookupInFirestore(
    String isbn, {
    required String schoolId,
  }) async {
    if (!_firestoreCacheReadEnabled) return null;
    try {
      final byNormalized = await _schoolBooks(schoolId)
          .where('isbnNormalized', isEqualTo: isbn)
          .limit(1)
          .get();

      if (byNormalized.docs.isNotEmpty) {
        return BookModel.fromFirestore(byNormalized.docs.first);
      }

      final byRaw = await _schoolBooks(schoolId)
          .where('isbn', isEqualTo: isbn)
          .limit(1)
          .get();

      if (byRaw.docs.isNotEmpty) {
        return BookModel.fromFirestore(byRaw.docs.first);
      }

      final legacy = await _lookupLegacyByIsbn(isbn, schoolId: schoolId);
      if (legacy != null) return legacy;
    } catch (e) {
      _handleFirestoreReadFailure(e, operation: 'Firestore lookup');
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

      final volumeInfo = (items[0] as Map<String, dynamic>)['volumeInfo']
          as Map<String, dynamic>?;
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
        genres: subjects?.take(5).map((s) => s.toString()).toList() ?? const [],
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
    if (!_firestoreCacheWriteEnabled) return;
    try {
      final ref = _schoolBooks(schoolId).doc('isbn_$isbn');
      final now = DateTime.now();

      await ref.set(
        {
          'title': book.title,
          'titleNormalized': normalizeTitle(book.title),
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
          // Append teacher to school library provenance (arrayUnion is a no-op for 'system')
          if (actorId.isNotEmpty && actorId != 'system')
            'scannedByTeacherIds': FieldValue.arrayUnion([actorId]),
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
      _handleFirestoreWriteFailure(e, operation: 'Cache write');
    }
  }

  /// Public API to materialize a book into a school's library collection.
  /// Used after inline community book creation to make the book immediately
  /// browsable/searchable in the teacher library without a second lookup pass.
  Future<void> materializeToSchoolLibrary({
    required String isbn,
    required BookModel book,
    required String source,
    required String schoolId,
    required String actorId,
  }) async {
    // Bypass the _firestoreCacheWriteEnabled flag — this is an explicit write
    try {
      final ref = _schoolBooks(schoolId).doc('isbn_$isbn');
      final now = DateTime.now();

      await ref.set(
        {
          'title': book.title,
          'titleNormalized': normalizeTitle(book.title),
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
          if (actorId.isNotEmpty && actorId != 'system')
            'scannedByTeacherIds': FieldValue.arrayUnion([actorId]),
          'metadata': {
            'source': source,
            'placeholder': false,
            'resolvedAt': Timestamp.fromDate(now),
          },
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('BookLookupService: materializeToSchoolLibrary failed: $e');
    }
  }

  // ─── Title-based Firestore lookup ───────────────────────

  Future<BookModel?> _lookupByTitleInFirestore(
    String normalizedTitle, {
    required String schoolId,
    String? originalTitle,
  }) async {
    if (!_firestoreCacheReadEnabled) return null;
    try {
      final query = await _schoolBooks(schoolId)
          .where('titleNormalized', isEqualTo: normalizedTitle)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        return BookModel.fromFirestore(query.docs.first);
      }

      final title = originalTitle?.trim();
      if (title != null && title.isNotEmpty) {
        final exactTitleQuery = await _schoolBooks(schoolId)
            .where('title', isEqualTo: title)
            .limit(1)
            .get();

        if (exactTitleQuery.docs.isNotEmpty) {
          final doc = exactTitleQuery.docs.first;
          final data = doc.data();
          if ((data['titleNormalized'] as String?)?.isNotEmpty != true) {
            unawaited(
              doc.reference.set(
                {'titleNormalized': normalizedTitle},
                SetOptions(merge: true),
              ).catchError((_) {}),
            );
          }
          return BookModel.fromFirestore(doc);
        }
      }

      final legacy = await _lookupLegacyByTitle(
        normalizedTitle: normalizedTitle,
        schoolId: schoolId,
        originalTitle: title,
      );
      if (legacy != null) return legacy;
    } catch (e) {
      _handleFirestoreReadFailure(e, operation: 'Title Firestore lookup');
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

      final volumeInfo = (items[0] as Map<String, dynamic>)['volumeInfo']
          as Map<String, dynamic>?;
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
      final identifiers = volumeInfo['industryIdentifiers'] as List<dynamic>?;
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
        isbn = isbns
            .firstWhere(
              (i) => i.toString().length == 13,
              orElse: () => isbns.first,
            )
            .toString();
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
        genres: subjects?.take(5).map((s) => s.toString()).toList() ?? const [],
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
    if (!_firestoreCacheWriteEnabled) return;
    try {
      final ref = _schoolBooks(schoolId).doc(book.id);
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
      _handleFirestoreWriteFailure(e, operation: 'Title cache write');
    }
  }

  Future<void> _cacheNotFoundByTitle({
    required String normalizedTitle,
    required String originalTitle,
    required String schoolId,
    required String actorId,
  }) async {
    if (!_firestoreCacheWriteEnabled) return;
    try {
      final ref = _schoolBooks(schoolId).doc('title_$normalizedTitle');
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
      _handleFirestoreWriteFailure(e, operation: 'Not-found cache write');
    }
  }

  // ─── Helpers ─────────────────────────────────────────────

  bool _isFirestorePermissionDenied(Object error) {
    if (error is FirebaseException) {
      return error.plugin == 'cloud_firestore' &&
          error.code == 'permission-denied';
    }

    final text = error.toString();
    return text.contains('[cloud_firestore/permission-denied]') ||
        text.contains('permission-denied');
  }

  Future<BookModel?> _lookupLegacyByIsbn(
    String isbn, {
    required String schoolId,
  }) async {
    final byNormalized = await _legacyBooks
        .where('isbnNormalized', isEqualTo: isbn)
        .where('schoolId', isEqualTo: schoolId)
        .limit(1)
        .get();
    if (byNormalized.docs.isNotEmpty) {
      return BookModel.fromFirestore(byNormalized.docs.first);
    }

    final byRaw = await _legacyBooks
        .where('isbn', isEqualTo: isbn)
        .where('schoolId', isEqualTo: schoolId)
        .limit(1)
        .get();
    if (byRaw.docs.isNotEmpty) {
      return BookModel.fromFirestore(byRaw.docs.first);
    }

    return null;
  }

  Future<BookModel?> _lookupLegacyByTitle({
    required String normalizedTitle,
    required String schoolId,
    String? originalTitle,
  }) async {
    final byNormalized = await _legacyBooks
        .where('titleNormalized', isEqualTo: normalizedTitle)
        .where('schoolId', isEqualTo: schoolId)
        .limit(1)
        .get();
    if (byNormalized.docs.isNotEmpty) {
      return BookModel.fromFirestore(byNormalized.docs.first);
    }

    if (originalTitle != null && originalTitle.isNotEmpty) {
      final exactTitle = await _legacyBooks
          .where('title', isEqualTo: originalTitle)
          .where('schoolId', isEqualTo: schoolId)
          .limit(1)
          .get();
      if (exactTitle.docs.isNotEmpty) {
        return BookModel.fromFirestore(exactTitle.docs.first);
      }
    }

    return null;
  }

  void _handleFirestoreReadFailure(
    Object error, {
    required String operation,
  }) {
    if (_isFirestorePermissionDenied(error)) {
      _firestoreCacheReadEnabled = false;
      if (!_didLogReadPermissionDenial) {
        _didLogReadPermissionDenial = true;
        debugPrint(
          'BookLookupService: Firestore cache reads disabled '
          '(permission-denied).',
        );
      }
      return;
    }
    debugPrint('BookLookupService: $operation failed: $error');
  }

  void _handleFirestoreWriteFailure(
    Object error, {
    required String operation,
  }) {
    if (_isFirestorePermissionDenied(error)) {
      _firestoreCacheWriteEnabled = false;
      if (!_didLogWritePermissionDenial) {
        _didLogWritePermissionDenial = true;
        debugPrint(
          'BookLookupService: Firestore cache writes disabled '
          '(permission-denied).',
        );
      }
      return;
    }
    debugPrint('BookLookupService: $operation failed: $error');
  }

  static String _normalizeIsbnForLookup(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) return '';

    final cleaned = trimmed.toUpperCase().replaceAll(RegExp(r'[^0-9X]'), '');
    if (cleaned.length == 10 && _isValidIsbn10(cleaned)) {
      return _convertIsbn10To13(cleaned);
    }

    if (cleaned.length == 13 && _isValidIsbn13(cleaned)) {
      return cleaned;
    }

    return cleaned.isEmpty ? trimmed : cleaned;
  }

  static bool _isValidIsbn10(String isbn10) {
    if (isbn10.length != 10) return false;

    var sum = 0;
    for (var i = 0; i < 10; i++) {
      final char = isbn10[i];
      final value = (i == 9 && char == 'X') ? 10 : int.tryParse(char);
      if (value == null) return false;
      sum += value * (10 - i);
    }

    return sum % 11 == 0;
  }

  static bool _isValidIsbn13(String isbn13) {
    if (isbn13.length != 13 || !RegExp(r'^\d{13}$').hasMatch(isbn13)) {
      return false;
    }

    var sum = 0;
    for (var i = 0; i < 12; i++) {
      final digit = int.parse(isbn13[i]);
      sum += i.isEven ? digit : digit * 3;
    }
    final checkDigit = (10 - (sum % 10)) % 10;
    return checkDigit == int.parse(isbn13[12]);
  }

  static String _convertIsbn10To13(String isbn10) {
    final stem = '978${isbn10.substring(0, 9)}';
    final checkDigit = _calculateIsbn13CheckDigit(stem);
    return '$stem$checkDigit';
  }

  static int _calculateIsbn13CheckDigit(String stem12) {
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      final digit = int.parse(stem12[i]);
      sum += i.isEven ? digit : digit * 3;
    }
    return (10 - (sum % 10)) % 10;
  }

  static bool _hasUsableCoverUrl(String? coverUrl) {
    if (coverUrl == null) return false;
    final trimmed = coverUrl.trim();
    return trimmed.isNotEmpty && trimmed.startsWith('http');
  }

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
