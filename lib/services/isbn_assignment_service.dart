import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/models/book_model.dart';
import 'book_lookup_service.dart';

class IsbnAssignmentService {
  IsbnAssignmentService({
    FirebaseFirestore? firestore,
    BookLookupService? bookLookupService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _bookLookupService = bookLookupService ??
            BookLookupService(firestore: firestore);

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
      final isbns = (metadata?['scannedIsbns'] as List?)
              ?.whereType<String>()
              .toList() ??
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
      final existingScannedIsbns = (existingMetadata['scannedIsbns'] as List?)
              ?.whereType<String>()
              .toSet() ??
          <String>{};

      final mergedTitles = <String>{...existingTitles};
      final mergedBookIds = <String>{...existingBookIds};
      final newBooks = <ScannedIsbnBook>[];
      final duplicateIsbns = <String>[];

      for (final isbn in byIsbn.keys) {
        if (existingScannedIsbns.contains(isbn)) {
          duplicateIsbns.add(isbn);
          continue;
        }

        final book = byIsbn[isbn]!;
        newBooks.add(book);
        mergedTitles.add(book.title);
        if (book.bookId != null && book.bookId!.isNotEmpty) {
          mergedBookIds.add(book.bookId!);
        }
      }

      final mergedIsbns = <String>{
        ...existingScannedIsbns,
        ...byIsbn.keys,
      };

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
        totalAssignedBooks: mergedTitles.length,
      );
    });
  }

  Future<ScannedIsbnBook> _resolveBookByIsbn({
    required String isbn,
    required String schoolId,
    required String actorId,
  }) async {
    // Try the full lookup chain: Firestore cache → Google Books → Open Library
    BookModel? resolved;
    try {
      resolved = await _bookLookupService.lookupByIsbn(
        isbn: isbn,
        schoolId: schoolId,
        actorId: actorId,
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
      title: 'Unknown Book (ISBN $isbn)',
      bookId: createdBookId,
      resolvedFromCatalog: false,
    );
  }

  Future<String> _createPlaceholderBook({
    required String isbn,
    required String schoolId,
    required String actorId,
  }) async {
    final ref = _firestore.collection('books').doc('isbn_$isbn');
    final now = DateTime.now();

    await ref.set(
      {
        'title': 'Unknown Book (ISBN $isbn)',
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
  });

  final String isbn;
  final String title;
  final String? author;
  final String? coverImageUrl;
  final String? bookId;
  final bool resolvedFromCatalog;
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
