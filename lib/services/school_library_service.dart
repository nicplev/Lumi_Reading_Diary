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

/// Provides access to the school-wide book library stored at
/// `schools/{schoolId}/books`.
///
/// Every book scanned by any teacher at the school is automatically added
/// to this collection by [BookLookupService._cacheBookInFirestore].
/// This service reads that collection and exposes it for the library UI.
class SchoolLibraryService {
  SchoolLibraryService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _booksRef(String schoolId) =>
      _firestore.collection('schools').doc(schoolId).collection('books');

  Query<Map<String, dynamic>> _legacyBooksRef(String schoolId) =>
      _firestore.collection('books').where('schoolId', isEqualTo: schoolId);

  /// Real-time stream of all books in the school library.
  /// Placeholders and unresolved stubs are excluded.
  ///
  /// The app is mid-migration from legacy top-level `/books` documents to the
  /// nested `schools/{schoolId}/books` collection. Read both sources so older
  /// schools still render their library while the data is being backfilled.
  Stream<List<BookModel>> booksStream(String schoolId) {
    final scopedSchoolId = schoolId.trim();
    if (scopedSchoolId.isEmpty) {
      return Stream.value(const <BookModel>[]);
    }

    late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
        nestedSubscription;
    late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
        legacySubscription;

    final controller = StreamController<List<BookModel>>();
    var nestedBooks = const <BookModel>[];
    var legacyBooks = const <BookModel>[];
    var nestedSettled = false;
    var legacySettled = false;
    var nestedFailed = false;
    var legacyFailed = false;

    void emitIfReady() {
      if (!nestedSettled || !legacySettled || controller.isClosed) return;

      if (nestedFailed && legacyFailed) {
        controller.addError(
          StateError(
              'Could not load school library from any Firestore source.'),
        );
        return;
      }

      controller.add(_mergeBooks(primary: nestedBooks, fallback: legacyBooks));
    }

    controller.onListen = () {
      nestedSubscription = _booksRef(scopedSchoolId).snapshots().listen(
        (snapshot) {
          nestedBooks = _decodeSnapshot(snapshot, sourceLabel: 'nested');
          nestedSettled = true;
          nestedFailed = false;
          emitIfReady();
        },
        onError: (Object error, StackTrace stackTrace) {
          nestedBooks = const <BookModel>[];
          nestedSettled = true;
          nestedFailed = true;
          debugPrint(
            'SchoolLibraryService: nested books stream failed for '
            '$scopedSchoolId: $error',
          );
          emitIfReady();
        },
      );

      legacySubscription = _legacyBooksRef(scopedSchoolId).snapshots().listen(
        (snapshot) {
          legacyBooks = _decodeSnapshot(snapshot, sourceLabel: 'legacy');
          legacySettled = true;
          legacyFailed = false;
          emitIfReady();
        },
        onError: (Object error, StackTrace stackTrace) {
          legacyBooks = const <BookModel>[];
          legacySettled = true;
          legacyFailed = true;
          debugPrint(
            'SchoolLibraryService: legacy books stream failed for '
            '$scopedSchoolId: $error',
          );
          emitIfReady();
        },
      );
    };

    controller.onCancel = () async {
      await nestedSubscription.cancel();
      await legacySubscription.cancel();
    };

    return controller.stream;
  }

  List<BookModel> _decodeSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    required String sourceLabel,
  }) {
    final books = <BookModel>[];

    for (final doc in snapshot.docs) {
      try {
        final book = BookModel.fromFirestore(doc);
        if (_isDisplayable(book)) books.add(book);
      } catch (error) {
        debugPrint(
          'SchoolLibraryService: skipping malformed $sourceLabel '
          'book ${doc.id}: $error',
        );
      }
    }

    return books;
  }

  List<BookModel> _mergeBooks({
    required List<BookModel> primary,
    required List<BookModel> fallback,
  }) {
    final mergedById = <String, BookModel>{};

    for (final book in fallback) {
      mergedById[book.id] = book;
    }
    for (final book in primary) {
      mergedById[book.id] = book;
    }

    final books = mergedById.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return books;
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
