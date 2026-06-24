import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/services/isbn_assignment_service.dart';

/// Verifies the in-classroom kiosk scan classification: renew vs already-on-list
/// vs already-read vs new. Uses fake Firestore so no network is hit.
void main() {
  const schoolId = 'school1';
  const studentId = 'studentA';
  // A fixed Wednesday so week maths is deterministic (week starts Monday).
  final referenceDate = DateTime(2026, 6, 24);
  final weekStart = IsbnAssignmentService.startOfWeek(referenceDate);
  final prevWeekStart = weekStart.subtract(const Duration(days: 7));

  late FakeFirebaseFirestore firestore;
  late IsbnAssignmentService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = IsbnAssignmentService(firestore: firestore);
  });

  CollectionReference<Map<String, dynamic>> allocations() => firestore
      .collection('schools')
      .doc(schoolId)
      .collection('allocations');

  Future<void> seedAllocation({
    required DateTime week,
    required String isbn,
    bool deleted = false,
  }) async {
    final id = IsbnAssignmentService.buildWeeklyAllocationId(
      studentId: studentId,
      weekStart: week,
    );
    await allocations().doc(id).set({
      'schoolId': schoolId,
      'studentIds': [studentId],
      'startDate': Timestamp.fromDate(week),
      'assignmentItems': [
        {
          'id': 'isbn_$isbn',
          'title': 'Book $isbn',
          'isbn': isbn,
          'bookId': 'isbn_$isbn',
          'isDeleted': deleted,
        },
      ],
    });
  }

  Future<ScanClassificationResult> classify(String isbn) => service.classifyScan(
        schoolId: schoolId,
        studentId: studentId,
        isbn: isbn,
        bookId: 'isbn_$isbn',
        referenceDate: referenceDate,
      );

  test('renew when the book was on the immediately-prior week list', () async {
    await seedAllocation(week: prevWeekStart, isbn: '9780000000001');

    final result = await classify('9780000000001');

    expect(result.classification, ScanClassification.renew);
    expect(
      result.prevAllocationId,
      IsbnAssignmentService.buildWeeklyAllocationId(
        studentId: studentId,
        weekStart: prevWeekStart,
      ),
    );
  });

  test('alreadyThisWeek when the book is already on this week list', () async {
    await seedAllocation(week: weekStart, isbn: '9780000000002');

    final result = await classify('9780000000002');

    expect(result.classification, ScanClassification.alreadyThisWeek);
  });

  test('alreadyRead when a reading-history entry exists from before', () async {
    await firestore.collection('bookReadingHistory').add({
      'studentId': studentId,
      'bookId': 'isbn_9780000000003',
      'completedAt': Timestamp.fromDate(DateTime(2026, 5, 1)),
      'isCompleted': true,
    });

    final result = await classify('9780000000003');

    expect(result.classification, ScanClassification.alreadyRead);
    expect(result.lastReadAt, DateTime(2026, 5, 1));
  });

  test('newBook when the book has never been seen', () async {
    final result = await classify('9780000000004');

    expect(result.classification, ScanClassification.newBook);
  });

  test('renew takes precedence over an existing reading-history entry',
      () async {
    // On last week's list AND in history — a rescan should continue it, not
    // nag with an "already read" notice.
    await seedAllocation(week: prevWeekStart, isbn: '9780000000005');
    await firestore.collection('bookReadingHistory').add({
      'studentId': studentId,
      'bookId': 'isbn_9780000000005',
      'startedAt': Timestamp.fromDate(DateTime(2026, 5, 1)),
      'isCompleted': false,
    });

    final result = await classify('9780000000005');

    expect(result.classification, ScanClassification.renew);
  });

  test('a deleted prior-week item does not count as a renewal', () async {
    await seedAllocation(
      week: prevWeekStart,
      isbn: '9780000000006',
      deleted: true,
    );

    final result = await classify('9780000000006');

    expect(result.classification, ScanClassification.newBook);
  });
}
