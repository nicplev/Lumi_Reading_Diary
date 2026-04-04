import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/models/allocation_model.dart';
import '../data/models/book_model.dart';
import 'book_lookup_service.dart';

class IsbnAssignmentService {
  IsbnAssignmentService({
    FirebaseFirestore? firestore,
    BookLookupService? bookLookupService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _bookLookupService =
            bookLookupService ?? BookLookupService(firestore: firestore);

  final FirebaseFirestore _firestore;
  final BookLookupService _bookLookupService;

  static DateTime startOfWeek(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized
        .subtract(Duration(days: normalized.weekday - DateTime.monday));
  }

  static DateTime endOfWeek(DateTime date) {
    final weekStart = startOfWeek(date);
    return DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day,
      23,
      59,
      59,
    ).add(const Duration(days: 6));
  }

  static String buildWeeklyAllocationId({
    required String studentId,
    required DateTime weekStart,
  }) {
    final dateStamp =
        '${weekStart.year.toString().padLeft(4, '0')}${weekStart.month.toString().padLeft(2, '0')}${weekStart.day.toString().padLeft(2, '0')}';
    return 'isbn_${studentId}_$dateStamp';
  }

  static String? normalizeIsbn(String? rawValue) {
    if (rawValue == null || rawValue.trim().isEmpty) {
      return null;
    }

    final cleaned = rawValue.toUpperCase().replaceAll(RegExp(r'[^0-9X]'), '');
    if (cleaned.length == 10) {
      if (!_isValidIsbn10(cleaned)) return null;
      return _convertIsbn10To13(cleaned);
    }

    if (cleaned.length == 13 && _isValidIsbn13(cleaned)) {
      // ISBN-13 is a subset of EAN-13. For books we only accept 978/979.
      if (cleaned.startsWith('978') || cleaned.startsWith('979')) {
        return cleaned;
      }
    }

    return null;
  }

  Future<IsbnAssignmentResult> assignIsbnsToStudentWeek({
    required String schoolId,
    required String classId,
    required String studentId,
    required String teacherId,
    required List<String> rawCodes,
    int targetMinutes = 20,
    String? sessionId,
    DateTime? targetDate,
  }) async {
    final invalidCodes = <String>[];
    final normalized = <String>{};

    for (final raw in rawCodes) {
      final isbn = normalizeIsbn(raw);
      if (isbn == null) {
        if (raw.trim().isNotEmpty) invalidCodes.add(raw);
        continue;
      }
      normalized.add(isbn);
    }

    if (normalized.isEmpty) {
      return IsbnAssignmentResult(
        allocationId: buildWeeklyAllocationId(
          studentId: studentId,
          weekStart: startOfWeek(targetDate ?? DateTime.now()),
        ),
        processedBooks: const [],
        newlyAssignedBooks: const [],
        duplicateIsbns: const [],
        invalidCodes: invalidCodes,
        totalAssignedBooks: 0,
      );
    }

    final resolvedBooks = <ScannedIsbnBook>[];
    for (final isbn in normalized) {
      resolvedBooks.add(
        await _resolveBookByIsbn(
          isbn: isbn,
          schoolId: schoolId,
          actorId: teacherId,
        ),
      );
    }

    final referenceDate = targetDate ?? DateTime.now();
    final weekStart = startOfWeek(referenceDate);
    final weekEnd = endOfWeek(referenceDate);
    final allocationId =
        buildWeeklyAllocationId(studentId: studentId, weekStart: weekStart);

    final summary = await _upsertWeeklyAllocation(
      schoolId: schoolId,
      classId: classId,
      studentId: studentId,
      teacherId: teacherId,
      allocationId: allocationId,
      weekStart: weekStart,
      weekEnd: weekEnd,
      targetMinutes: targetMinutes,
      books: resolvedBooks,
      sessionId: sessionId,
    );

    return IsbnAssignmentResult(
      allocationId: allocationId,
      processedBooks: resolvedBooks,
      newlyAssignedBooks: summary.newlyAssignedBooks,
      duplicateIsbns: summary.duplicateIsbns,
      invalidCodes: invalidCodes,
      totalAssignedBooks: summary.totalAssignedBooks,
    );
  }

  /// Resolve a single ISBN without creating placeholders.
  /// Returns [IsbnResolved], [IsbnNotFound], or [IsbnInvalid].
  Future<IsbnResolutionResult> resolveIsbn({
    required String rawCode,
    required String schoolId,
    required String teacherId,
  }) async {
    final isbn = normalizeIsbn(rawCode);
    if (isbn == null) return IsbnInvalid(rawCode);

    bool isNewToLibrary = false;
    try {
      final existingDoc = await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('books')
          .doc('isbn_$isbn')
          .get();
      isNewToLibrary = !existingDoc.exists ||
          existingDoc.data()?['metadata']?['placeholder'] == true;
    } catch (_) {}

    BookModel? resolved;
    try {
      resolved = await _bookLookupService.lookupByIsbn(
        isbn: isbn,
        schoolId: schoolId,
        actorId: teacherId,
        useDeviceScanCache: true,
        persistToDeviceScanCache: true,
      );
    } catch (_) {
      resolved = null;
    }

    if (resolved != null && resolved.metadata?['placeholder'] != true) {
      return IsbnResolved(ScannedIsbnBook(
        isbn: isbn,
        title: resolved.title,
        author: resolved.author,
        coverImageUrl: resolved.coverImageUrl,
        bookId: resolved.id,
        resolvedFromCatalog: true,
        isNewToLibrary: isNewToLibrary,
      ));
    }

    return IsbnNotFound(isbn);
  }

  /// Assign already-resolved books to a student's weekly allocation.
  Future<IsbnAssignmentResult> assignResolvedBooks({
    required String schoolId,
    required String classId,
    required String studentId,
    required String teacherId,
    required List<ScannedIsbnBook> books,
    int targetMinutes = 20,
    String? sessionId,
    DateTime? targetDate,
  }) async {
    final referenceDate = targetDate ?? DateTime.now();
    final weekStart = startOfWeek(referenceDate);
    final weekEnd = endOfWeek(referenceDate);
    final allocationId =
        buildWeeklyAllocationId(studentId: studentId, weekStart: weekStart);

    final summary = await _upsertWeeklyAllocation(
      schoolId: schoolId,
      classId: classId,
      studentId: studentId,
      teacherId: teacherId,
      allocationId: allocationId,
      weekStart: weekStart,
      weekEnd: weekEnd,
      targetMinutes: targetMinutes,
      books: books,
      sessionId: sessionId,
    );

    return IsbnAssignmentResult(
      allocationId: allocationId,
      processedBooks: books,
      newlyAssignedBooks: summary.newlyAssignedBooks,
      duplicateIsbns: summary.duplicateIsbns,
      invalidCodes: const [],
      totalAssignedBooks: summary.totalAssignedBooks,
    );
  }

  /// Returns the set of student IDs that already have ISBN-scan allocations
  /// for the week containing [referenceDate] in the given class.
  Future<Set<String>> getAssignedStudentIdsForWeek({
    required String schoolId,
    required String classId,
    required DateTime referenceDate,
  }) async {
    final weekStart = startOfWeek(referenceDate);
    final snapshot = await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('allocations')
        .where('classId', isEqualTo: classId)
        .where('startDate', isEqualTo: Timestamp.fromDate(weekStart))
        .get();

    final assignedIds = <String>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final ids =
          (data['studentIds'] as List?)?.whereType<String>() ?? <String>[];
      assignedIds.addAll(ids);
    }
    return assignedIds;
  }

  /// Returns a map of ISBN → number of students who already have that ISBN
  /// assigned for the week containing [referenceDate] in the given class.
  Future<Map<String, int>> countStudentsWithIsbnsForWeek({
    required String schoolId,
    required String classId,
    required DateTime referenceDate,
  }) async {
    final weekStart = startOfWeek(referenceDate);
    final snapshot = await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('allocations')
        .where('classId', isEqualTo: classId)
        .where('startDate', isEqualTo: Timestamp.fromDate(weekStart))
        .get();

    final isbnCounts = <String, int>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final metadata = data['metadata'] as Map<String, dynamic>?;
      final isbns =
          (metadata?['scannedIsbns'] as List?)?.whereType<String>().toList() ??
              <String>[];
      for (final isbn in isbns) {
        isbnCounts[isbn] = (isbnCounts[isbn] ?? 0) + 1;
      }
    }
    return isbnCounts;
  }

  Future<_AllocationUpsertSummary> _upsertWeeklyAllocation({
    required String schoolId,
    required String classId,
    required String studentId,
    required String teacherId,
    required String allocationId,
    required DateTime weekStart,
    required DateTime weekEnd,
    required int targetMinutes,
    required List<ScannedIsbnBook> books,
    String? sessionId,
  }) async {
    final ref = _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('allocations')
        .doc(allocationId);

    final now = DateTime.now();
    final byIsbn = {for (final book in books) book.isbn: book};

    return _firestore.runTransaction<_AllocationUpsertSummary>((txn) async {
      final snapshot = await txn.get(ref);
      final existingData = snapshot.data();

      final existingTitles = (existingData?['bookTitles'] as List?)
              ?.whereType<String>()
              .toList() ??
          <String>[];
      final existingBookIds =
          (existingData?['bookIds'] as List?)?.whereType<String>().toList() ??
              <String>[];
      final existingMetadata = Map<String, dynamic>.from(
        (existingData?['metadata'] as Map<String, dynamic>?) ??
            const <String, dynamic>{},
      );
      final existingAssignmentItems = AllocationModel.parseAssignmentItems(
        existingData?['assignmentItems'],
        legacyBookTitles: existingTitles,
        legacyBookIds: existingBookIds,
      );
      final mergedAssignmentItems =
          List<AllocationBookItem>.from(existingAssignmentItems);
      final existingItemIds = mergedAssignmentItems
          .map((item) => item.id.trim())
          .where((id) => id.isNotEmpty)
          .toSet();
      final existingActiveItemIsbns = mergedAssignmentItems
          .where((item) => !item.isDeleted)
          .map((item) => item.resolvedIsbn)
          .whereType<String>()
          .map((isbn) => isbn.trim())
          .where((isbn) => isbn.isNotEmpty)
          .toSet();
      final newBooks = <ScannedIsbnBook>[];
      final duplicateIsbns = <String>[];

      for (final isbn in byIsbn.keys) {
        // Only treat as duplicate if the ISBN is in an ACTIVE (non-deleted)
        // assignment item. Previously this also checked metadata.scannedIsbns,
        // which never gets cleaned up on deletion — causing deleted books to
        // be permanently un-reassignable.
        if (existingActiveItemIsbns.contains(isbn)) {
          duplicateIsbns.add(isbn);
          continue;
        }

        final book = byIsbn[isbn]!;
        newBooks.add(book);
        var itemId = 'isbn_$isbn';
        if (existingItemIds.contains(itemId)) {
          itemId =
              'isbn_${isbn}_${now.millisecondsSinceEpoch}_${newBooks.length}';
        }
        existingItemIds.add(itemId);

        mergedAssignmentItems.add(
          AllocationBookItem(
            id: itemId,
            title: book.title,
            bookId: (book.bookId != null && book.bookId!.trim().isNotEmpty)
                ? book.bookId!.trim()
                : 'isbn_$isbn',
            isbn: isbn,
            addedAt: now,
            addedBy: teacherId,
            metadata: {
              'source': 'isbn_scan',
              'resolvedFromCatalog': book.resolvedFromCatalog,
            },
          ),
        );
        existingActiveItemIsbns.add(isbn);
      }

      final activeItems = mergedAssignmentItems
          .where((item) => !item.isDeleted && item.title.trim().isNotEmpty)
          .toList(growable: false);
      // Rebuild scannedIsbns from active items only, so deleted book ISBNs
      // are cleared and can be re-scanned later.
      final mergedIsbns = <String>{
        ...activeItems
            .map((item) => item.resolvedIsbn)
            .whereType<String>()
            .map((isbn) => isbn.trim())
            .where((isbn) => isbn.isNotEmpty),
        ...byIsbn.keys,
      };
      final mergedTitles = activeItems
          .map((item) => item.title.trim())
          .where((title) => title.isNotEmpty)
          .toSet();
      final mergedBookIds = activeItems
          .map((item) => item.bookId?.trim())
          .whereType<String>()
          .where((bookId) => bookId.isNotEmpty)
          .toSet();

      final updatedMetadata = <String, dynamic>{
        ...existingMetadata,
        'source': 'isbn_scan',
        'scannedIsbns': mergedIsbns.toList(),
        'lastScanAt': Timestamp.fromDate(now),
        'lastScanBy': teacherId,
      };
      if (sessionId != null && sessionId.isNotEmpty) {
        updatedMetadata['lastScanSessionId'] = sessionId;
      }

      final createdAt = existingData?['createdAt'] as Timestamp?;
      final createdBy = existingData?['createdBy'] as String?;

      txn.set(
        ref,
        {
          'schoolId': schoolId,
          'classId': classId,
          'teacherId': teacherId,
          'studentIds': [studentId],
          'type': 'byTitle',
          'cadence': 'weekly',
          'targetMinutes': targetMinutes,
          'startDate': Timestamp.fromDate(weekStart),
          'endDate': Timestamp.fromDate(weekEnd),
          'bookIds': mergedBookIds.toList(),
          'bookTitles': mergedTitles.toList(),
          'assignmentItems':
              mergedAssignmentItems.map((item) => item.toMap()).toList(),
          'schemaVersion': 2,
          'isRecurring': false,
          'isActive': true,
          'createdAt': createdAt ?? Timestamp.fromDate(now),
          'createdBy': createdBy ?? teacherId,
          'metadata': updatedMetadata,
        },
        SetOptions(merge: true),
      );

      return _AllocationUpsertSummary(
        newlyAssignedBooks: newBooks,
        duplicateIsbns: duplicateIsbns,
        totalAssignedBooks: activeItems.length,
      );
    });
  }

  Future<ScannedIsbnBook> _resolveBookByIsbn({
    required String isbn,
    required String schoolId,
    required String actorId,
  }) async {
    // Check if this book is already in the school library before resolving
    bool isNewToLibrary = false;
    try {
      final existingDoc = await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('books')
          .doc('isbn_$isbn')
          .get();
      isNewToLibrary = !existingDoc.exists ||
          existingDoc.data()?['metadata']?['placeholder'] == true;
    } catch (_) {
      // Non-critical — default to false
    }

    // Try the full lookup chain: Firestore cache → Google Books → Open Library
    BookModel? resolved;
    try {
      resolved = await _bookLookupService.lookupByIsbn(
        isbn: isbn,
        schoolId: schoolId,
        actorId: actorId,
        useDeviceScanCache: true,
        persistToDeviceScanCache: true,
      );
    } catch (_) {
      resolved = null;
    }

    if (resolved != null && resolved.metadata?['placeholder'] != true) {
      return ScannedIsbnBook(
        isbn: isbn,
        title: resolved.title,
        author: resolved.author,
        coverImageUrl: resolved.coverImageUrl,
        bookId: resolved.id,
        resolvedFromCatalog: true,
        isNewToLibrary: isNewToLibrary,
      );
    }

    // All APIs failed — create a placeholder
    String? createdBookId;
    try {
      createdBookId = await _createPlaceholderBook(
        isbn: isbn,
        schoolId: schoolId,
        actorId: actorId,
      );
    } catch (_) {
      // Placeholder creation is best-effort; assignment should still succeed.
    }

    return ScannedIsbnBook(
      isbn: isbn,
      title: placeholderTitle,
      bookId: createdBookId,
      resolvedFromCatalog: false,
      isNewToLibrary: isNewToLibrary,
    );
  }

  /// Human-readable label used for ISBN-scanned books whose metadata could
  /// not be resolved from any source.
  static const String placeholderTitle = 'Unrecognised Book';

  /// Returns a clean display title, converting any legacy
  /// "Unknown Book (ISBN ...)" entries to [placeholderTitle].
  static String sanitizeDisplayTitle(String title) {
    if (title.startsWith('Unknown Book (ISBN ')) return placeholderTitle;
    return title;
  }

  Future<String> _createPlaceholderBook({
    required String isbn,
    required String schoolId,
    required String actorId,
  }) async {
    final ref = _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('books')
        .doc('isbn_$isbn');
    final now = DateTime.now();

    await ref.set(
      {
        'title': placeholderTitle,
        'titleNormalized': BookLookupService.normalizeTitle(placeholderTitle),
        'isbn': isbn,
        'isbnNormalized': isbn,
        'author': null,
        'coverImageUrl': null,
        'description': null,
        'genres': <String>[],
        'tags': <String>[],
        'createdAt': Timestamp.fromDate(now),
        'addedBy': actorId,
        'schoolId': schoolId,
        'metadata': {
          'source': 'isbn_scan',
          'placeholder': true,
          'placeholderCreatedAt': Timestamp.fromDate(now),
        },
      },
      SetOptions(merge: true),
    );

    return ref.id;
  }

  /// Reassigns existing books into a future week's allocation.
  ///
  /// Used when a teacher wants a student to keep reading the same book(s)
  /// for another cycle. Maps each [AllocationBookItem] to a
  /// [ScannedIsbnBook] and delegates to [_upsertWeeklyAllocation] so that
  /// deduplication and merge logic is reused.
  Future<ReassignmentResult> reassignBooksToNextCycle({
    required String schoolId,
    required String classId,
    required String studentId,
    required String teacherId,
    required List<AllocationBookItem> itemsToKeep,
    required String sourceAllocationId,
    DateTime? targetDate,
    int targetMinutes = 20,
  }) async {
    if (itemsToKeep.isEmpty) {
      return const ReassignmentResult(
        allocationId: '',
        keptCount: 0,
        alreadyAssignedCount: 0,
      );
    }

    final effectiveTarget = targetDate ?? DateTime.now().add(const Duration(days: 7));
    final weekStart = startOfWeek(effectiveTarget);
    final weekEnd = endOfWeek(effectiveTarget);
    final allocationId = buildWeeklyAllocationId(
      studentId: studentId,
      weekStart: weekStart,
    );

    final books = itemsToKeep.map((item) {
      return ScannedIsbnBook(
        isbn: item.resolvedIsbn ?? '',
        title: item.title,
        bookId: item.bookId,
        coverImageUrl: null,
        resolvedFromCatalog: true,
      );
    }).toList();

    final summary = await _upsertWeeklyAllocation(
      schoolId: schoolId,
      classId: classId,
      studentId: studentId,
      teacherId: teacherId,
      allocationId: allocationId,
      weekStart: weekStart,
      weekEnd: weekEnd,
      targetMinutes: targetMinutes,
      books: books,
    );

    return ReassignmentResult(
      allocationId: allocationId,
      keptCount: summary.newlyAssignedBooks.length,
      alreadyAssignedCount: summary.duplicateIsbns.length,
    );
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
}

class ScannedIsbnBook {
  const ScannedIsbnBook({
    required this.isbn,
    required this.title,
    this.author,
    this.coverImageUrl,
    this.bookId,
    required this.resolvedFromCatalog,
    this.isNewToLibrary = false,
  });

  final String isbn;
  final String title;
  final String? author;
  final String? coverImageUrl;
  final String? bookId;
  final bool resolvedFromCatalog;

  /// True if this book was first scanned into the school library by this operation.
  final bool isNewToLibrary;

  ScannedIsbnBook copyWith({
    String? isbn,
    String? title,
    String? author,
    String? coverImageUrl,
    String? bookId,
    bool? resolvedFromCatalog,
    bool? isNewToLibrary,
  }) {
    return ScannedIsbnBook(
      isbn: isbn ?? this.isbn,
      title: title ?? this.title,
      author: author ?? this.author,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      bookId: bookId ?? this.bookId,
      resolvedFromCatalog: resolvedFromCatalog ?? this.resolvedFromCatalog,
      isNewToLibrary: isNewToLibrary ?? this.isNewToLibrary,
    );
  }
}

/// Result of resolving a single ISBN without creating placeholders.
sealed class IsbnResolutionResult {
  const IsbnResolutionResult();
}

class IsbnResolved extends IsbnResolutionResult {
  const IsbnResolved(this.book);
  final ScannedIsbnBook book;
}

class IsbnNotFound extends IsbnResolutionResult {
  const IsbnNotFound(this.isbn);
  final String isbn;
}

class IsbnInvalid extends IsbnResolutionResult {
  const IsbnInvalid(this.rawCode);
  final String rawCode;
}

class IsbnAssignmentResult {
  const IsbnAssignmentResult({
    required this.allocationId,
    required this.processedBooks,
    required this.newlyAssignedBooks,
    required this.duplicateIsbns,
    required this.invalidCodes,
    required this.totalAssignedBooks,
  });

  final String allocationId;
  final List<ScannedIsbnBook> processedBooks;
  final List<ScannedIsbnBook> newlyAssignedBooks;
  final List<String> duplicateIsbns;
  final List<String> invalidCodes;
  final int totalAssignedBooks;
}

class ReassignmentResult {
  const ReassignmentResult({
    required this.allocationId,
    required this.keptCount,
    required this.alreadyAssignedCount,
  });

  final String allocationId;
  final int keptCount;
  final int alreadyAssignedCount;
}

class _AllocationUpsertSummary {
  const _AllocationUpsertSummary({
    required this.newlyAssignedBooks,
    required this.duplicateIsbns,
    required this.totalAssignedBooks,
  });

  final List<ScannedIsbnBook> newlyAssignedBooks;
  final List<String> duplicateIsbns;
  final int totalAssignedBooks;
}
