import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/models/book_model.dart';

/// How a book's reading level should be displayed for a given school.
enum LevelDisplayMode {
  /// School has explicitly set their own level for this book.
  schoolOverride,
  /// Community level uses the same schema as this school — show normally.
  communityMatch,
  /// Community level uses a different schema — show with schema label.
  communityMismatch,
  /// No level information available.
  none,
}

/// Header counts shown on the library screen — kept on a single denormalized
/// doc at `schools/{id}/libraryMeta/counts` so the library screen doesn't
/// have to read the entire books collection to render the badges.
class LibraryCounts {
  const LibraryCounts({
    required this.total,
    required this.decodable,
  });

  static const empty = LibraryCounts(total: 0, decodable: 0);

  final int total;
  final int decodable;

  int get library => (total - decodable).clamp(0, total);
}

/// A page of books plus the cursor needed to fetch the next page.
class BookPage {
  const BookPage({
    required this.books,
    required this.lastDocId,
    required this.hasMore,
  });

  final List<BookModel> books;
  final String? lastDocId; // null when the first page is empty
  final bool hasMore;
}

/// Provides access to the school-wide book library stored at
/// `schools/{schoolId}/books`.
///
/// Every book scanned by any teacher at the school is automatically added
/// to this collection by `BookLookupService._cacheBookInFirestore`.
///
/// **History:** Pre-2026-06 this service merged real-time streams over
/// the nested `schools/{schoolId}/books` collection AND a legacy top-level
/// `/books` collection (filtered by `schoolId`). That worked, but each
/// library-screen open subscribed to the full nested collection (5000+
/// reads for an established school) and the per-document listener kept
/// firing on every book change for the lifetime of the StreamBuilder.
///
/// The current pipeline:
///  - paginates the nested collection in 50-doc pages
///  - drops the legacy `/books` listener entirely (migration complete)
///  - relies on a denormalized `libraryMeta/counts` doc for header badges,
///    maintained server-side by the `maintainLibraryCounts` Cloud Function
class SchoolLibraryService {
  SchoolLibraryService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Page size for paginated fetches. Picked to keep first-paint snappy on
  /// large libraries while still loading enough that most filter chips
  /// surface a handful of results from the initial page.
  static const int pageSize = 50;

  CollectionReference<Map<String, dynamic>> _booksRef(String schoolId) =>
      _firestore.collection('schools').doc(schoolId).collection('books');

  DocumentReference<Map<String, dynamic>> _countsRef(String schoolId) =>
      _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('libraryMeta')
          .doc('counts');

  /// Fetches a paginated page of books, newest first.
  ///
  /// Pass `startAfterDocId` from the previous page's [BookPage.lastDocId]
  /// to fetch the next page. The returned [BookPage.hasMore] is `true`
  /// when the page is full — call again with the new cursor to continue.
  Future<BookPage> fetchBooksPage(
    String schoolId, {
    int limit = pageSize,
    String? startAfterDocId,
  }) async {
    final scopedSchoolId = schoolId.trim();
    if (scopedSchoolId.isEmpty) {
      return const BookPage(books: [], lastDocId: null, hasMore: false);
    }

    Query<Map<String, dynamic>> query = _booksRef(scopedSchoolId)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (startAfterDocId != null && startAfterDocId.isNotEmpty) {
      final cursorDoc = await _booksRef(scopedSchoolId)
          .doc(startAfterDocId)
          .get(const GetOptions(source: Source.serverAndCache));
      if (cursorDoc.exists) {
        query = query.startAfterDocument(cursorDoc);
      }
    }

    final snapshot = await query
        .get(const GetOptions(source: Source.serverAndCache));

    final books = <BookModel>[];
    for (final doc in snapshot.docs) {
      try {
        final book = BookModel.fromFirestore(doc);
        if (_isDisplayable(book)) books.add(book);
      } catch (error) {
        debugPrint(
          'SchoolLibraryService: skipping malformed book ${doc.id}: $error',
        );
      }
    }

    return BookPage(
      books: books,
      lastDocId: snapshot.docs.isEmpty ? null : snapshot.docs.last.id,
      hasMore: snapshot.docs.length >= limit,
    );
  }

  /// Reads the denormalized counts doc maintained by the
  /// `maintainLibraryCounts` Cloud Function. Falls back to
  /// [LibraryCounts.empty] if the doc hasn't been seeded yet.
  Future<LibraryCounts> fetchCounts(String schoolId) async {
    final scopedSchoolId = schoolId.trim();
    if (scopedSchoolId.isEmpty) return LibraryCounts.empty;

    final snap = await _countsRef(scopedSchoolId)
        .get(const GetOptions(source: Source.serverAndCache));
    final data = snap.data();
    if (data == null) return LibraryCounts.empty;
    final total = (data['total'] as num?)?.toInt() ?? 0;
    final decodable = (data['decodable'] as num?)?.toInt() ?? 0;
    return LibraryCounts(total: total, decodable: decodable);
  }

  static bool _isDisplayable(BookModel book) =>
      book.metadata?['placeholder'] != true &&
      book.title.isNotEmpty &&
      book.title != 'Unrecognised Book';

  // ─── Client-side filter / search helpers ───────────────────────────────────

  static const String typeDecodable = 'decodable';
  static const String typeLibrary = 'library';

  /// Returns whether a book came from the LLLL decodable catalog or was
  /// manually tagged as decodable by a teacher.
  static bool isDecodable(BookModel book) =>
      book.metadata?['llllProductCode'] != null ||
      book.metadata?['isDecodable'] == true;

  /// Applies active filter chip + search query to a list of books.
  static List<BookModel> applyFilter({
    required List<BookModel> books,
    required String filter,
    required String searchQuery,
  }) {
    var result = books;

    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      result = result
          .where((b) =>
              b.title.toLowerCase().contains(q) ||
              (b.author?.toLowerCase().contains(q) ?? false) ||
              (b.isbn?.contains(q) ?? false))
          .toList();
    }

    switch (filter) {
      case 'Decodable':
        return result.where(isDecodable).toList();
      case 'Library':
        return result.where((b) => !isDecodable(b)).toList();
      case 'Recently Added':
        final sorted = List<BookModel>.from(result)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return sorted.take(20).toList();
      default:
        return result;
    }
  }

  /// Groups decodable books by reading level, sorted correctly across all
  /// supported grading schemas (LLLL stages, numbered levels, Reading Doctor,
  /// phases, and custom labels). "Uncategorised" always appears last.
  static Map<String, List<BookModel>> groupDecodableByStage(
      List<BookModel> books) {
    final decodable = books.where(isDecodable).toList();
    final grouped = <String, List<BookModel>>{};
    for (final book in decodable) {
      final stage = book.readingLevel?.isNotEmpty == true
          ? book.readingLevel!
          : 'Uncategorised';
      grouped.putIfAbsent(stage, () => []).add(book);
    }
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        if (a == 'Uncategorised') return 1;
        if (b == 'Uncategorised') return -1;
        return _levelSortKey(a).compareTo(_levelSortKey(b));
      });
    return {for (final k in sortedKeys) k: grouped[k]!};
  }

  /// Numeric sort key for a reading level string, schema-agnostic.
  ///
  /// • "Stage Plus 4" → 3.5  (slots between Stage 3 and Stage 4)
  /// • Reading Doctor "1A"/"2C" → part×10 + letter offset (10, 11, 12, 20…)
  /// • All other schemas → leading integer × 1.0
  /// • Unrecognised → 999 (sorted to end before "Uncategorised")
  static double _levelSortKey(String level) {
    if (level == 'Stage Plus 4') return 3.5;

    // Reading Doctor alphanumeric (1A, 1B, 1C, 2A, 2B, 2C)
    final rdMatch = RegExp(r'^(\d)([A-C])$').firstMatch(level);
    if (rdMatch != null) {
      final part = double.tryParse(rdMatch.group(1)!) ?? 1;
      final letter =
          (rdMatch.group(2)!.codeUnitAt(0) - 'A'.codeUnitAt(0)).toDouble();
      return part * 10 + letter;
    }

    final n = _leadingInt(level);
    return n?.toDouble() ?? 999;
  }

  static int? _leadingInt(String s) {
    final match = RegExp(r'\d+').firstMatch(s);
    return match != null ? int.tryParse(match.group(0)!) : null;
  }

  /// Returns all non-decodable books (library books, picture books, etc.).
  static List<BookModel> libraryBooks(List<BookModel> books) =>
      books.where((b) => !isDecodable(b)).toList();

  // ─── Schema-aware level resolution ───────────────────────────────────────

  /// Resolves the reading level to display for [book] in the context of a
  /// school whose level schema key is [schoolLevelSchemaKey]
  /// (e.g., 'pmBenchmark', 'aToZ', 'llll_stages').
  ///
  /// Priority:
  /// 1. schoolReadingLevel — the school's own explicit override.
  /// 2. readingLevel when communityLevelSchema matches schoolLevelSchemaKey.
  /// 3. readingLevel from a different schema — returned with a short label.
  /// 4. null when there is no level data.
  static ({String? level, LevelDisplayMode mode}) resolveDisplayLevel(
    BookModel book,
    String? schoolLevelSchemaKey,
  ) {
    // 1. School override always wins.
    if (book.schoolReadingLevel?.isNotEmpty == true) {
      return (level: book.schoolReadingLevel, mode: LevelDisplayMode.schoolOverride);
    }

    final communityLevel = book.readingLevel;
    if (communityLevel == null || communityLevel.isEmpty) {
      return (level: null, mode: LevelDisplayMode.none);
    }

    final communitySchema = book.communityLevelSchema;

    // 2. No schema provenance (legacy data) or schemas match — show normally.
    if (communitySchema == null ||
        communitySchema.isEmpty ||
        communitySchema == schoolLevelSchemaKey) {
      return (level: communityLevel, mode: LevelDisplayMode.communityMatch);
    }

    // 3. Schema mismatch — show with a short schema label.
    final label = schemaDisplayName(communitySchema);
    return (
      level: '$communityLevel · $label',
      mode: LevelDisplayMode.communityMismatch,
    );
  }

  /// Short display name for a level schema key.
  static String schemaDisplayName(String schemaKey) {
    switch (schemaKey) {
      case 'aToZ':         return 'A–Z';
      case 'pmBenchmark':  return 'PM';
      case 'lexile':       return 'Lexile';
      case 'numbered':     return 'Numbered';
      case 'namedLevels':  return 'Custom';
      case 'colouredLevels': return 'Custom';
      case 'custom':       return 'Custom';
      case 'llll_stages':  return 'LLLL';
      case 'levels':       return 'Levels';
      case 'reading_doctor': return 'RD';
      case 'phases':       return 'Phases';
      default:             return 'Other';
    }
  }

  // ─── Stage colour helper ──────────────────────────────────────────────────

  /// Colour palette cycled by level index. Covers 12 entries so Dandelion /
  /// DRA levels 1-12 each get a distinct colour without repetition.
  static const List<int> _stageHues = [
    0xFFEF5350, //  1 — red
    0xFFFF9800, //  2 — orange
    0xFFFDD835, //  3 — yellow
    0xFF66BB6A, //  4 — green
    0xFF42A5F5, //  5 — blue
    0xFFAB47BC, //  6 — purple
    0xFF26C6DA, //  7 — cyan
    0xFFFF7043, //  8 — deep orange
    0xFF8D6E63, //  9 — brown
    0xFF78909C, // 10 — blue-grey
    0xFF4DB6AC, // 11 — teal
    0xFF7986CB, // 12 — indigo
  ];

  // Distinct colour for the LLLL bridge stage (not a numeric index).
  static const int _stagePlus4Color = 0xFF80DEEA; // light teal

  /// Returns an ARGB int colour for [level] suitable for use as a [Color].
  ///
  /// Handles all supported schemas:
  /// • "Stage Plus 4" → dedicated bridge teal
  /// • Reading Doctor "1A"/"2C" → colour by part number (1 or 2)
  /// • All others → colour by leading integer, cycling through the palette
  static int stageColor(String level) {
    if (level == 'Stage Plus 4') return _stagePlus4Color;

    // Reading Doctor: colour by part (1A/1B/1C share one colour, 2A/2B/2C share another)
    final rdMatch = RegExp(r'^(\d)[A-C]$').firstMatch(level);
    if (rdMatch != null) {
      final part = (int.tryParse(rdMatch.group(1)!) ?? 1) - 1;
      return _stageHues[part % _stageHues.length];
    }

    final n = (_leadingInt(level) ?? 1) - 1;
    return _stageHues[n.clamp(0, _stageHues.length - 1)];
  }
}
