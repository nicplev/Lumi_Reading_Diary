import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/models/reading_log_model.dart';

/// Stable cursor for a reading-history page.
///
/// Reading dates are not unique. Firestore indexes add the document name as
/// their final deterministic tie-breaker, and a document-snapshot cursor
/// carries both that name and the ordered date into the next query.
class ReadingHistoryCursor {
  const ReadingHistoryCursor._({
    required this.date,
    required this.documentId,
    required DocumentSnapshot<Map<String, dynamic>> snapshot,
  }) : _snapshot = snapshot;

  factory ReadingHistoryCursor.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return ReadingHistoryCursor._(
      date: snapshot.get('date') as Timestamp,
      documentId: snapshot.id,
      snapshot: snapshot,
    );
  }

  final DocumentSnapshot<Map<String, dynamic>> _snapshot;

  /// Exposed for diagnostics and durable cursor serialization if a future UI
  /// needs to persist its position across app launches.
  final Timestamp date;
  final String documentId;
}

class ReadingHistoryPage {
  const ReadingHistoryPage({
    required this.logs,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<ReadingLogModel> logs;
  final ReadingHistoryCursor? nextCursor;
  final bool hasMore;
}

/// Bounded, tenant-scoped access to a student's reading-log history.
class ReadingHistoryService {
  ReadingHistoryService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const int pageSize = 30;
  static const int maxPageSize = 100;

  final FirebaseFirestore _firestore;

  Future<ReadingHistoryPage> fetchStudentPage({
    required String schoolId,
    required String studentId,
    String? classId,
    ReadingHistoryCursor? startAfter,
    int limit = pageSize,
  }) async {
    final scopedSchoolId = schoolId.trim();
    final scopedStudentId = studentId.trim();
    final scopedClassId = classId?.trim();
    if (scopedSchoolId.isEmpty || scopedStudentId.isEmpty) {
      return const ReadingHistoryPage(
        logs: [],
        nextCursor: null,
        hasMore: false,
      );
    }
    if (limit < 1 || limit > maxPageSize) {
      throw RangeError.range(limit, 1, maxPageSize, 'limit');
    }

    Query<Map<String, dynamic>> query = _firestore
        .collection('schools')
        .doc(scopedSchoolId)
        .collection('readingLogs')
        .where('studentId', isEqualTo: scopedStudentId);

    // Teacher Rules require class-scoped queries. Parent callers omit classId
    // because their authorization is tied to the requested student instead.
    if (scopedClassId != null && scopedClassId.isNotEmpty) {
      query = query.where('classId', isEqualTo: scopedClassId);
    }

    query = query
        // Firestore's index appends __name__ (document ID) in the same
        // direction as this final order field. startAfterDocument therefore
        // produces the required stable (date, documentId) cursor.
        .orderBy('date', descending: true)
        .limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter._snapshot);
    }

    final snapshot =
        await query.get(const GetOptions(source: Source.serverAndCache));
    final pageDocs = snapshot.docs;
    final logs = pageDocs.map(ReadingLogModel.fromFirestore).toList();
    final last = pageDocs.isEmpty ? null : pageDocs.last;

    return ReadingHistoryPage(
      logs: logs,
      nextCursor: last == null ? null : ReadingHistoryCursor.fromSnapshot(last),
      // A full page may require one final (empty) bounded fetch to prove EOF.
      hasMore: snapshot.docs.length == limit,
    );
  }
}
