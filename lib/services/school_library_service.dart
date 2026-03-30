import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/models/book_model.dart';

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

  /// Returns whether a book came from the LLLL decodable catalog.
  static bool isDecodable(BookModel book) =>
      book.metadata?['source'] == 'llll_local_db';

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

  /// Groups LLLL decodable books by reading stage, sorted alphabetically by stage.
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
    // Sort stages: "Stage 1", "Stage 2", … then "Uncategorised" last
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        if (a == 'Uncategorised') return 1;
        if (b == 'Uncategorised') return -1;
        final aNum = _stageNumber(a);
        final bNum = _stageNumber(b);
        if (aNum != null && bNum != null) return aNum.compareTo(bNum);
        return a.compareTo(b);
      });
    return {for (final k in sortedKeys) k: grouped[k]!};
  }

  static int? _stageNumber(String stage) {
    final match = RegExp(r'\d+').firstMatch(stage);
    return match != null ? int.tryParse(match.group(0)!) : null;
  }

  /// Returns all non-LLLL books (library books, picture books, etc.).
  static List<BookModel> libraryBooks(List<BookModel> books) =>
      books.where((b) => !isDecodable(b)).toList();

  // ─── Stage colour helper (mirrors the LLLL stage palette) ─────────────────

  static const List<int> _stageHues = [
    0xFFEF5350, // Stage 1 — red
    0xFFFF9800, // Stage 2 — orange
    0xFFFDD835, // Stage 3 — yellow
    0xFF66BB6A, // Stage 4 — green
    0xFF42A5F5, // Stage 5 — blue
    0xFFAB47BC, // Stage 6 — purple
    0xFF26C6DA, // Stage 7 — cyan
    0xFFFF7043, // Stage 8 — deep orange
  ];

  static int stageColor(String stage) {
    final n = (_stageNumber(stage) ?? 1) - 1;
    return _stageHues[n % _stageHues.length];
  }
}
