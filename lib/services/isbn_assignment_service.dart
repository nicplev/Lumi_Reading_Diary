import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

import '../core/services/demo_session_service.dart';
import '../core/services/service_status_controller.dart';
import '../data/models/allocation_model.dart';
import '../data/models/book_model.dart';
import 'book_lookup_service.dart';
import 'offline_service.dart';

class IsbnAssignmentService {
  IsbnAssignmentService({
    FirebaseFirestore? firestore,
    BookLookupService? bookLookupService,
    Future<DemoSessionContext?> Function({bool forceRefresh})?
        demoContextProvider,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _bookLookupService =
            bookLookupService ?? BookLookupService(firestore: firestore),
        _demoContextProvider =
            demoContextProvider ?? DemoSessionService.currentContext;

  final FirebaseFirestore _firestore;
  final BookLookupService _bookLookupService;
  final Future<DemoSessionContext?> Function({bool forceRefresh})
      _demoContextProvider;

  static const Set<String> _transientCodes = {
    'unavailable',
    'deadline-exceeded',
    'aborted',
    'cancelled',
  };

  /// Conservative classifier: authorization, validation and App Check errors
  /// are never converted into apparently-successful offline work.
  static bool isTransientAssignmentError(Object error) {
    if (error is SocketException || error is TimeoutException) return true;
    if (error is FirebaseException) {
      if (_transientCodes.contains(error.code)) return true;
      if (error.code != 'unknown' && error.code != 'internal') return false;
      return _looksLikeNetworkFailure(error.message);
    }
    if (error is PlatformException) {
      if (_transientCodes.contains(error.code)) return true;
      return _looksLikeNetworkFailure(error.message);
    }
    return false;
  }

  static bool _looksLikeNetworkFailure(String? message) {
    final value = (message ?? '').toLowerCase();
    return value.contains('unable to resolve host') ||
        value.contains('unknownhost') ||
        value.contains('network is unreachable') ||
        value.contains('connection reset') ||
        value.contains('connection refused') ||
        value.contains('failed to connect');
  }

  static String diagnosticCode(Object error) {
    if (error is FirebaseException) return 'firebase:${error.code}';
    if (error is PlatformException) return 'platform:${error.code}';
    if (error is SocketException) return 'network:socket';
    if (error is TimeoutException) return 'network:timeout';
    return 'unexpected:${error.runtimeType}';
  }

  Future<DemoSessionContext?> _demoContextForSchool(
    String schoolId, {
    bool forceRefresh = false,
  }) async {
    final context = await _demoContextProvider(forceRefresh: forceRefresh);
    if (context == null) return null;
    if (context.schoolId != schoolId) {
      throw FirebaseException(
        plugin: 'lumi-demo',
        code: 'permission-denied',
        message: 'Demo school mismatch.',
      );
    }
    return context;
  }

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

  static String buildDemoWeeklyAllocationId({
    required String studentId,
    required DateTime weekStart,
  }) {
    return 'demo_${buildWeeklyAllocationId(studentId: studentId, weekStart: weekStart)}';
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
    final demoContext = await _demoContextForSchool(schoolId);
    final allocationId = demoContext == null
        ? buildWeeklyAllocationId(studentId: studentId, weekStart: weekStart)
        : buildDemoWeeklyAllocationId(
            studentId: studentId,
            weekStart: weekStart,
          );

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
      demoContext: demoContext,
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
    var lookupFailed = false;
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
      lookupFailed = true;
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

    // Distinguish "couldn't check right now" (offline / lookup threw) from a
    // genuinely unknown ISBN. Previously a network failure collapsed to
    // IsbnNotFound, so a real book scanned offline read as "couldn't find that
    // book." Only call it not-found when we could actually reach the catalog.
    if (resolved == null &&
        (lookupFailed ||
            !ServiceStatusController.instance.current.canWriteToFirebase)) {
      return IsbnLookupUnavailable(isbn);
    }

    return IsbnNotFound(isbn);
  }

  /// Assign already-resolved books to a student's weekly allocation.
  ///
  /// [renewedIsbns] — newly-added items whose ISBN is in this set are tagged
  /// `metadata.renewed = true` so the UI can show a "Renewed" badge. Defaults
  /// to empty, so existing callers are unaffected.
  Future<IsbnAssignmentResult> assignResolvedBooks({
    required String schoolId,
    required String classId,
    required String studentId,
    required String teacherId,
    required List<ScannedIsbnBook> books,
    int targetMinutes = 20,
    String? sessionId,
    DateTime? targetDate,
    Set<String> renewedIsbns = const <String>{},
  }) async {
    final demoContext = await _demoContextForSchool(schoolId);
    // Offline: the write runs a Firestore transaction, which throws with no
    // connection (transactions can't run from cache) — so a scan used to be
    // silently lost. Queue it and replay on reconnect (replayQueuedAssignment),
    // mirroring the reading-log offline queue.
    if (!ServiceStatusController.instance.current.canWriteToFirebase) {
      return _queueAssignmentOffline(
        schoolId: schoolId,
        classId: classId,
        studentId: studentId,
        teacherId: teacherId,
        books: books,
        targetMinutes: targetMinutes,
        sessionId: sessionId,
        targetDate: targetDate,
        renewedIsbns: renewedIsbns,
        demoContext: demoContext,
      );
    }
    try {
      return await _writeResolvedBooks(
        schoolId: schoolId,
        classId: classId,
        studentId: studentId,
        teacherId: teacherId,
        books: books,
        targetMinutes: targetMinutes,
        sessionId: sessionId,
        targetDate: targetDate,
        renewedIsbns: renewedIsbns,
        demoContext: demoContext,
      );
    } catch (e) {
      // The health signal said we could write, but the transaction couldn't
      // reach the backend (connectivity dropped between the check and the
      // commit, or the health probe simply lagged reality). A transaction can't
      // buffer to the local cache like a plain set() — it throws instead of
      // deferring — so without this the scan would surface a generic error and
      // be lost unless the teacher re-scanned. Re-queue it instead. The replay
      // is idempotent: _upsertWeeklyAllocation dedupes by ACTIVE ISBN, so even a
      // write that secretly committed before its ack failed won't double-add.
      if (e is FirebaseException && e.code == 'permission-denied') {
        // A just-reprovisioned demo or cold restored auth session may still
        // carry the old token. Refresh once, then fail hard if Rules still deny.
        final refreshedContext = await _demoContextForSchool(
          schoolId,
          forceRefresh: true,
        );
        try {
          return await _writeResolvedBooks(
            schoolId: schoolId,
            classId: classId,
            studentId: studentId,
            teacherId: teacherId,
            books: books,
            targetMinutes: targetMinutes,
            sessionId: sessionId,
            targetDate: targetDate,
            renewedIsbns: renewedIsbns,
            demoContext: refreshedContext,
          );
        } catch (retryError) {
          if (isTransientAssignmentError(retryError)) {
            return _queueAssignmentOffline(
              schoolId: schoolId,
              classId: classId,
              studentId: studentId,
              teacherId: teacherId,
              books: books,
              targetMinutes: targetMinutes,
              sessionId: sessionId,
              targetDate: targetDate,
              renewedIsbns: renewedIsbns,
              demoContext: refreshedContext,
            );
          }
          rethrow;
        }
      }
      if (isTransientAssignmentError(e)) {
        return _queueAssignmentOffline(
          schoolId: schoolId,
          classId: classId,
          studentId: studentId,
          teacherId: teacherId,
          books: books,
          targetMinutes: targetMinutes,
          sessionId: sessionId,
          targetDate: targetDate,
          renewedIsbns: renewedIsbns,
          demoContext: demoContext,
        );
      }
      rethrow;
    }
  }

  /// Enqueues an assignment for offline replay and returns the queued result.
  /// Shared by the offline-guard branch and the network-failure fallback in
  /// [assignResolvedBooks] so both paths serialise + shape the result identically.
  Future<IsbnAssignmentResult> _queueAssignmentOffline({
    required String schoolId,
    required String classId,
    required String studentId,
    required String teacherId,
    required List<ScannedIsbnBook> books,
    int targetMinutes = 20,
    String? sessionId,
    DateTime? targetDate,
    Set<String> renewedIsbns = const <String>{},
    DemoSessionContext? demoContext,
  }) async {
    await OfflineService.instance.enqueueAllocationAssignment(
      schoolId: schoolId,
      classId: classId,
      studentId: studentId,
      teacherId: teacherId,
      books: books.map((b) => b.toMap()).toList(),
      targetMinutes: targetMinutes,
      sessionId: sessionId,
      targetDateMs: targetDate?.millisecondsSinceEpoch,
      renewedIsbns: renewedIsbns.toList(),
      demoGenerationId: demoContext?.generationId,
    );
    final referenceDate = targetDate ?? DateTime.now();
    final weekStart = startOfWeek(referenceDate);
    final allocationId = demoContext == null
        ? buildWeeklyAllocationId(studentId: studentId, weekStart: weekStart)
        : buildDemoWeeklyAllocationId(
            studentId: studentId,
            weekStart: weekStart,
          );
    return IsbnAssignmentResult(
      allocationId: allocationId,
      processedBooks: books,
      newlyAssignedBooks: books,
      duplicateIsbns: const [],
      invalidCodes: const [],
      totalAssignedBooks: books.length,
      queuedOffline: true,
    );
  }

  /// The actual transaction write, WITHOUT the offline guard. Called by
  /// [assignResolvedBooks] when online and by the offline drain replay (which
  /// only runs on a healthy write path), so it always reaches Firestore.
  Future<IsbnAssignmentResult> _writeResolvedBooks({
    required String schoolId,
    required String classId,
    required String studentId,
    required String teacherId,
    required List<ScannedIsbnBook> books,
    int targetMinutes = 20,
    String? sessionId,
    DateTime? targetDate,
    Set<String> renewedIsbns = const <String>{},
    DemoSessionContext? demoContext,
  }) async {
    final referenceDate = targetDate ?? DateTime.now();
    final weekStart = startOfWeek(referenceDate);
    final weekEnd = endOfWeek(referenceDate);
    final allocationId = demoContext == null
        ? buildWeeklyAllocationId(studentId: studentId, weekStart: weekStart)
        : buildDemoWeeklyAllocationId(
            studentId: studentId,
            weekStart: weekStart,
          );

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
      renewedIsbns: renewedIsbns,
      demoContext: demoContext,
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

  /// Replays an assignment that was queued offline: deserialises the queued
  /// payload and runs the write. The drain only fires on a healthy write path,
  /// so this always writes (it deliberately skips the offline guard). Registered
  /// on [OfflineService] at app startup.
  Future<void> replayQueuedAssignment(Map<String, dynamic> data) async {
    final books = ((data['books'] as List?) ?? const [])
        .map((b) => ScannedIsbnBook.fromMap(b as Map))
        .toList();
    final targetDateMs = data['targetDateMs'] as int?;
    final schoolId = data['schoolId'] as String;
    final queuedGenerationId = data['demoGenerationId'] as String?;
    final currentDemo = await _demoContextForSchool(
      schoolId,
      forceRefresh: true,
    );
    if (queuedGenerationId != null && currentDemo == null) {
      // A failed token refresh is not proof that the demo was reprovisioned.
      // Keep the item retryable until we can compare two concrete generation
      // values; otherwise a brief auth/network outage would park valid work.
      throw FirebaseException(
        plugin: 'lumi-demo',
        code: 'unavailable',
        message: 'Could not verify the current demo generation.',
      );
    }
    if ((currentDemo != null && queuedGenerationId == null) ||
        (queuedGenerationId != null &&
            currentDemo!.generationId != queuedGenerationId)) {
      throw FirebaseException(
        plugin: 'lumi-demo',
        code: 'failed-precondition',
        message: 'This queued assignment expired when the demo was refreshed.',
      );
    }
    await _writeResolvedBooks(
      schoolId: schoolId,
      classId: data['classId'] as String,
      studentId: data['studentId'] as String,
      teacherId: data['teacherId'] as String,
      books: books,
      targetMinutes: (data['targetMinutes'] as int?) ?? 20,
      sessionId: data['sessionId'] as String?,
      targetDate: targetDateMs != null
          ? DateTime.fromMillisecondsSinceEpoch(targetDateMs)
          : null,
      renewedIsbns: ((data['renewedIsbns'] as List?) ?? const [])
          .whereType<String>()
          .toSet(),
      demoContext: currentDemo,
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
    Set<String> renewedIsbns = const <String>{},
    DemoSessionContext? demoContext,
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
              if (renewedIsbns.contains(isbn)) 'renewed': true,
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
          if (demoContext != null) ...{
            'demoEphemeral': true,
            'demoGenerationId': demoContext.generationId,
            'demoOrigin': 'flutter_camera',
          },
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

    final effectiveTarget =
        targetDate ?? DateTime.now().add(const Duration(days: 7));
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
      // A carry-over to the next cycle is a renewal — tag the items so the
      // "Renewed" badge shows for teacher-initiated renewals too.
      renewedIsbns: books.map((b) => b.isbn).where((i) => i.isNotEmpty).toSet(),
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

  /// Returns true if the student has a bookReadingHistory entry matching
  /// the given bookId or isbn. Checks multiple ID variants to handle both
  /// scanner-sourced ('isbn_{isbn}') and library-sourced (school book ID) formats.
  /// Always returns false on any error so a check failure never blocks assignment.
  /// Batched replacement for calling [studentHasPreviouslyReadBook] once per
  /// (student × book): returns, for each student, the set of `bookId` values in
  /// their reading history. Callers then check any number of books in memory
  /// instead of doing N-students × M-books sequential point reads (which was
  /// ~500 serial Firestore reads before a "select-all" allocation save).
  /// Reads in `whereIn` batches of 30 (the Firestore cap) → ceil(N/30) queries.
  Future<Map<String, Set<String>>> readBookIdsForStudents(
    List<String> studentIds,
  ) async {
    final result = <String, Set<String>>{
      for (final id in studentIds) id: <String>{},
    };
    for (var i = 0; i < studentIds.length; i += 30) {
      final end = i + 30 > studentIds.length ? studentIds.length : i + 30;
      final chunk = studentIds.sublist(i, end);
      if (chunk.isEmpty) continue;
      try {
        final snap = await _firestore
            .collection('bookReadingHistory')
            .where('studentId', whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          final data = doc.data();
          final sid = data['studentId'] as String?;
          final bid = data['bookId'] as String?;
          if (sid != null && bid != null) result[sid]?.add(bid);
        }
      } catch (_) {
        // Degrade gracefully — matches the old per-read catch returning false.
      }
    }
    return result;
  }

  Future<bool> studentHasPreviouslyReadBook({
    required String studentId,
    String? bookId,
    String? isbn,
  }) async {
    try {
      final variants = <String>{};
      if (bookId != null && bookId.isNotEmpty) variants.add(bookId);
      if (isbn != null && isbn.isNotEmpty) {
        variants.add(isbn);
        variants.add('isbn_$isbn');
      }
      if (variants.isEmpty) return false;

      for (final v in variants) {
        final snap = await _firestore
            .collection('bookReadingHistory')
            .where('studentId', isEqualTo: studentId)
            .where('bookId', isEqualTo: v)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Classifies a scanned book for the in-classroom kiosk flow, deciding how to
  /// react before it is added to the student's weekly list. Read-only — it does
  /// not write anything; callers still persist via [assignResolvedBooks].
  ///
  /// Order of checks (first match wins):
  ///  1. [ScanClassification.renew] — the book is on the student's *immediately
  ///     prior* week allocation, so a rescan continues it into this week.
  ///  2. [ScanClassification.alreadyThisWeek] — already on this week's list.
  ///  3. [ScanClassification.alreadyRead] — a [bookReadingHistory] entry exists
  ///     from an earlier week (re-reading is allowed; this just drives a notice).
  ///  4. [ScanClassification.newBook] — never seen before.
  ///
  /// Every lookup is wrapped so a failure degrades to [ScanClassification.newBook]
  /// and never blocks scanning.
  Future<ScanClassificationResult> classifyScan({
    required String schoolId,
    required String studentId,
    required String isbn,
    String? bookId,
    DateTime? referenceDate,
  }) async {
    final now = referenceDate ?? DateTime.now();
    final weekStart = startOfWeek(now);
    final prevWeekStart = weekStart.subtract(const Duration(days: 7));

    final allocations = _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('allocations');

    // 1. Renew — present on the immediately-prior week's list.
    try {
      final prevId = buildWeeklyAllocationId(
          studentId: studentId, weekStart: prevWeekStart);
      final prevSnap = await allocations.doc(prevId).get();
      if (prevSnap.exists && _allocationHasActiveIsbn(prevSnap.data(), isbn)) {
        return ScanClassificationResult(
          classification: ScanClassification.renew,
          prevAllocationId: prevId,
        );
      }
    } catch (_) {}

    // 2. Already on this week's list.
    try {
      final curId =
          buildWeeklyAllocationId(studentId: studentId, weekStart: weekStart);
      final curSnap = await allocations.doc(curId).get();
      if (curSnap.exists && _allocationHasActiveIsbn(curSnap.data(), isbn)) {
        return const ScanClassificationResult(
          classification: ScanClassification.alreadyThisWeek,
        );
      }
    } catch (_) {}

    // 3. Already read in an earlier week.
    try {
      final lastReadAt = await _findReadingHistoryDate(
        studentId: studentId,
        bookId: bookId,
        isbn: isbn,
      );
      if (lastReadAt != null) {
        return ScanClassificationResult(
          classification: ScanClassification.alreadyRead,
          lastReadAt: lastReadAt,
        );
      }
    } catch (_) {}

    return const ScanClassificationResult(
      classification: ScanClassification.newBook,
    );
  }

  /// True if [data] (a raw allocation document) has a non-deleted assignment
  /// item whose resolved ISBN matches [isbn].
  bool _allocationHasActiveIsbn(Map<String, dynamic>? data, String isbn) {
    if (data == null) return false;
    final items = AllocationModel.parseAssignmentItems(
      data['assignmentItems'],
      legacyBookTitles:
          (data['bookTitles'] as List?)?.whereType<String>().toList() ??
              const [],
      legacyBookIds:
          (data['bookIds'] as List?)?.whereType<String>().toList() ?? const [],
    );
    return items.any(
      (item) => !item.isDeleted && item.resolvedIsbn?.trim() == isbn,
    );
  }

  /// Returns the timestamp of a matching [bookReadingHistory] entry (preferring
  /// `completedAt`, falling back to `startedAt`), or null if none exists.
  /// A non-null result with no usable timestamp returns the Unix epoch so the
  /// caller can still treat the book as previously read.
  Future<DateTime?> _findReadingHistoryDate({
    required String studentId,
    String? bookId,
    String? isbn,
  }) async {
    final variants = <String>{};
    if (bookId != null && bookId.isNotEmpty) variants.add(bookId);
    if (isbn != null && isbn.isNotEmpty) {
      variants.add(isbn);
      variants.add('isbn_$isbn');
    }
    if (variants.isEmpty) return null;

    for (final v in variants) {
      final snap = await _firestore
          .collection('bookReadingHistory')
          .where('studentId', isEqualTo: studentId)
          .where('bookId', isEqualTo: v)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final d = snap.docs.first.data();
        final ts = (d['completedAt'] ?? d['startedAt']) as Timestamp?;
        return ts?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
      }
    }
    return null;
  }
}

/// How a scanned book relates to a student's reading history, used by the
/// in-classroom kiosk to choose its on-screen response. See
/// [IsbnAssignmentService.classifyScan].
enum ScanClassification { renew, alreadyThisWeek, alreadyRead, newBook }

class ScanClassificationResult {
  const ScanClassificationResult({
    required this.classification,
    this.prevAllocationId,
    this.lastReadAt,
  });

  final ScanClassification classification;

  /// The prior-week allocation id a renewal was carried from (when [renew]).
  final String? prevAllocationId;

  /// When the book was last read (when [alreadyRead]); the Unix epoch if a
  /// history entry exists but carried no usable timestamp.
  final DateTime? lastReadAt;
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

  /// Serialised form for the offline assignment sync queue.
  Map<String, dynamic> toMap() => {
        'isbn': isbn,
        'title': title,
        'author': author,
        'coverImageUrl': coverImageUrl,
        'bookId': bookId,
        'resolvedFromCatalog': resolvedFromCatalog,
        'isNewToLibrary': isNewToLibrary,
      };

  static ScannedIsbnBook fromMap(Map<dynamic, dynamic> map) => ScannedIsbnBook(
        isbn: (map['isbn'] as String?) ?? '',
        title: (map['title'] as String?) ?? '',
        author: map['author'] as String?,
        coverImageUrl: map['coverImageUrl'] as String?,
        bookId: map['bookId'] as String?,
        resolvedFromCatalog: map['resolvedFromCatalog'] as bool? ?? false,
        isNewToLibrary: map['isNewToLibrary'] as bool? ?? false,
      );
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

/// The catalog couldn't be reached to resolve the ISBN (offline / lookup
/// failed) — distinct from [IsbnNotFound], which means the catalog was reached
/// and genuinely had no match. Lets the scanner say "you're offline" instead of
/// mislabeling a real book as "couldn't find that book."
class IsbnLookupUnavailable extends IsbnResolutionResult {
  const IsbnLookupUnavailable(this.isbn);
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
    this.queuedOffline = false,
  });

  final String allocationId;
  final List<ScannedIsbnBook> processedBooks;
  final List<ScannedIsbnBook> newlyAssignedBooks;
  final List<String> duplicateIsbns;
  final List<String> invalidCodes;
  final int totalAssignedBooks;

  /// True when the write couldn't reach Firebase and was queued for sync
  /// instead — the caller should show a "saved, will sync" state rather than a
  /// confirmed assignment.
  final bool queuedOffline;
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
