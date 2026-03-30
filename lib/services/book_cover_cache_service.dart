import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/models/allocation_model.dart';
import 'book_lookup_service.dart';
import 'isbn_assignment_service.dart';

/// App-session singleton that caches cover-URL metadata resolved from
/// Firestore book documents.
///
/// Keeps results for the entire session (until the app is killed / swiped
/// away), so screens that display covers never re-query Firestore for a book
/// they have already seen.
///
/// Image *bytes* are handled separately by [PersistentImageCacheService],
/// which writes files to disk and survives across app launches.
///
/// Usage:
/// ```dart
/// // In initState:
/// BookCoverCacheService.instance.addListener(_onCoversUpdated);
///
/// // In dispose:
/// BookCoverCacheService.instance.removeListener(_onCoversUpdated);
///
/// // Trigger background fetches whenever allocations change:
/// BookCoverCacheService.instance.primeFromAllocations(activeAllocations, firestore);
///
/// // Look up a URL to pass to LumiBookCard:
/// final url = BookCoverCacheService.instance.resolveCoverUrl(title);
/// ```
class BookCoverCacheService extends ChangeNotifier {
  BookCoverCacheService._();

  static final BookCoverCacheService instance = BookCoverCacheService._();

  // isbn (normalized) → cover URL
  final Map<String, String> _isbnCoverCache = {};

  // isbn (normalized) → canonical title
  final Map<String, String> _titleByIsbn = {};

  // normalizedTitle → isbn — lets [resolveCoverUrl] prefer ISBN over title
  final Map<String, String> _isbnByNormalizedTitle = {};

  final Set<String> _bookDocsLoaded = {};
  final Set<String> _bookDocsLoading = {};

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Queue background Firestore fetches for every [bookId] referenced by
  /// [allocations] that has not been loaded yet this session.
  ///
  /// Safe to call on every widget rebuild — already-loaded IDs are skipped.
  void primeFromAllocations(
    List<AllocationModel> allocations,
    FirebaseFirestore firestore,
  ) {
    for (final allocation in allocations) {
      final schoolId = allocation.schoolId.trim();
      for (final rawId in allocation.bookIds ?? const <String>[]) {
        final id = rawId.trim();
        final docKey = _docKey(schoolId: schoolId, bookId: id);
        if (id.isEmpty ||
            _bookDocsLoaded.contains(docKey) ||
            _bookDocsLoading.contains(docKey)) {
          continue;
        }
        _bookDocsLoading.add(docKey);
        unawaited(_loadBookDocument(
          bookId: id,
          schoolId: schoolId,
          firestore: firestore,
        ));
      }
    }
  }

  /// Store cover metadata fetched via another path (e.g. the ISBN lookup API
  /// in StudentDetailScreen).  Calling this with a URL that is already cached
  /// under the same ISBN is a no-op.
  void cacheFromIsbnLookup({
    required String isbn,
    required String title,
    required String? coverImageUrl,
  }) {
    final normalizedIsbn =
        IsbnAssignmentService.normalizeIsbn(isbn) ?? isbn.trim();
    if (normalizedIsbn.isEmpty) return;

    final canonicalTitle = title.trim();
    final key = BookLookupService.normalizeTitle(canonicalTitle);
    var changed = false;

    if (_titleByIsbn[normalizedIsbn] != canonicalTitle) {
      _titleByIsbn[normalizedIsbn] = canonicalTitle;
      changed = true;
    }

    if (key.isNotEmpty && _isbnByNormalizedTitle[key] != normalizedIsbn) {
      _isbnByNormalizedTitle[key] = normalizedIsbn;
      changed = true;
    }

    final sanitizedUrl = _sanitizeCoverUrl(coverImageUrl);
    final fallbackUrl = _fallbackCoverUrlForIsbn(normalizedIsbn);
    final effectiveUrl = sanitizedUrl ?? fallbackUrl;

    if (effectiveUrl != null &&
        effectiveUrl.isNotEmpty &&
        effectiveUrl.startsWith('http')) {
      if (_isbnCoverCache[normalizedIsbn] != effectiveUrl) {
        _isbnCoverCache[normalizedIsbn] = effectiveUrl;
        changed = true;
      }
    }

    if (changed) notifyListeners();
  }

  /// Returns the best available cover URL for [title], or `null` if not yet
  /// resolved.  Only returns a URL when the title maps to a known ISBN —
  /// title-only fallback was removed to avoid fuzzy mismatches.
  String? resolveCoverUrl(String title) {
    final key = BookLookupService.normalizeTitle(title);
    if (key.isEmpty) return null;

    final isbn = _isbnByNormalizedTitle[key];
    if (isbn != null) {
      final url = _isbnCoverCache[isbn];
      if (url != null && url.startsWith('http')) return url;
    }

    return null;
  }

  /// Returns the cached cover URL for an ISBN if available.
  String? resolveCoverUrlByIsbn(String isbn) {
    final normalizedIsbn =
        IsbnAssignmentService.normalizeIsbn(isbn) ?? isbn.trim();
    if (normalizedIsbn.isEmpty) return null;
    final url = _isbnCoverCache[normalizedIsbn];
    return (url != null && url.startsWith('http')) ? url : null;
  }

  /// Returns the cached canonical title for an ISBN if available.
  String? resolveTitleByIsbn(String isbn) {
    final normalizedIsbn =
        IsbnAssignmentService.normalizeIsbn(isbn) ?? isbn.trim();
    if (normalizedIsbn.isEmpty) return null;
    return _titleByIsbn[normalizedIsbn];
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Internal
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadBookDocument({
    required String bookId,
    required String schoolId,
    required FirebaseFirestore firestore,
  }) async {
    final docKey = _docKey(schoolId: schoolId, bookId: bookId);
    try {
      final scopedSchoolId = schoolId.trim();
      DocumentSnapshot<Map<String, dynamic>> doc;

      if (scopedSchoolId.isNotEmpty) {
        doc = await firestore
            .collection('schools')
            .doc(scopedSchoolId)
            .collection('books')
            .doc(bookId)
            .get();
        if (!doc.exists) {
          doc = await firestore.collection('books').doc(bookId).get();
        }
      } else {
        doc = await firestore.collection('books').doc(bookId).get();
      }
      if (!doc.exists) return;
      final data = doc.data();
      if (data == null) return;

      final title = (data['title'] as String?)?.trim();
      if (title == null || title.isEmpty) return;

      final url = _sanitizeCoverUrl(data['coverImageUrl'] as String?);
      final rawIsbn = (data['isbnNormalized'] as String?) ??
          (data['isbn'] as String?) ??
          (bookId.startsWith('isbn_') ? bookId.substring(5) : null);
      final isbn = rawIsbn == null
          ? ''
          : (IsbnAssignmentService.normalizeIsbn(rawIsbn) ?? rawIsbn.trim());

      final key = BookLookupService.normalizeTitle(title);
      final fallbackUrl =
          isbn.isNotEmpty ? _fallbackCoverUrlForIsbn(isbn) : null;
      final effectiveUrl = url ?? fallbackUrl;
      var changed = false;

      if (isbn.isNotEmpty) {
        if (_titleByIsbn[isbn] != title) {
          _titleByIsbn[isbn] = title;
          changed = true;
        }
        if (key.isNotEmpty && _isbnByNormalizedTitle[key] != isbn) {
          _isbnByNormalizedTitle[key] = isbn;
          changed = true;
        }
        if (effectiveUrl != null &&
            effectiveUrl.isNotEmpty &&
            effectiveUrl.startsWith('http') &&
            _isbnCoverCache[isbn] != effectiveUrl) {
          _isbnCoverCache[isbn] = effectiveUrl;
          changed = true;
        }
      }

      if (changed) notifyListeners();
    } catch (_) {
      // Best-effort; keep placeholder on failure.
    } finally {
      _bookDocsLoading.remove(docKey);
      _bookDocsLoaded.add(docKey);
    }
  }

  String _docKey({
    required String schoolId,
    required String bookId,
  }) {
    return '$schoolId|$bookId';
  }

  String? _sanitizeCoverUrl(String? rawUrl) {
    final trimmed = rawUrl?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (!trimmed.startsWith('http')) return null;
    if (trimmed.startsWith('http://')) {
      return trimmed.replaceFirst('http://', 'https://');
    }
    return trimmed;
  }

  String? _fallbackCoverUrlForIsbn(String isbn) {
    final normalized = IsbnAssignmentService.normalizeIsbn(isbn) ?? isbn.trim();
    if (normalized.isEmpty) return null;
    return 'https://covers.openlibrary.org/b/isbn/$normalized-M.jpg?default=false';
  }
}
