import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/models/service_status.dart';
import 'package:lumi_reading_tracker/core/services/service_status_controller.dart';
import 'package:lumi_reading_tracker/services/isbn_assignment_service.dart';

/// Verifies that [IsbnAssignmentService.assignResolvedBooks] tags an item's
/// metadata with `renewed: true` only when its ISBN is in `renewedIsbns`.
void main() {
  const schoolId = 'school1';
  const classId = 'class1';
  const studentId = 'studentA';
  const isbn = '9780000000001';
  final targetDate = DateTime(2026, 6, 24);

  late FakeFirebaseFirestore firestore;
  late IsbnAssignmentService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = IsbnAssignmentService(firestore: firestore);
    // These assert the ONLINE write path (they read the written allocation
    // back). assignResolvedBooks queues offline unless the status is healthy,
    // so mark it healthy — matches reading_log_service_test.
    ServiceStatusController.instance
        .debugSetCurrent(ServiceStatusSnapshot.healthy());
  });

  tearDown(() {
    ServiceStatusController.instance
        .debugSetCurrent(ServiceStatusSnapshot.unknown());
  });

  Future<Map<String, dynamic>?> itemMetadata() async {
    final id = IsbnAssignmentService.buildWeeklyAllocationId(
      studentId: studentId,
      weekStart: IsbnAssignmentService.startOfWeek(targetDate),
    );
    final snap = await firestore
        .collection('schools')
        .doc(schoolId)
        .collection('allocations')
        .doc(id)
        .get();
    final items = (snap.data()?['assignmentItems'] as List?) ?? const [];
    final item = items.cast<Map<String, dynamic>>().firstWhere(
          (i) => i['isbn'] == isbn,
          orElse: () => <String, dynamic>{},
        );
    return item['metadata'] as Map<String, dynamic>?;
  }

  ScannedIsbnBook book() => const ScannedIsbnBook(
        isbn: isbn,
        title: 'A Book',
        resolvedFromCatalog: true,
      );

  test('tags renewed:true when the ISBN is in renewedIsbns', () async {
    await service.assignResolvedBooks(
      schoolId: schoolId,
      classId: classId,
      studentId: studentId,
      teacherId: 'teacher1',
      books: [book()],
      targetDate: targetDate,
      renewedIsbns: {isbn},
    );

    expect((await itemMetadata())?['renewed'], true);
  });

  test('does not tag renewed when renewedIsbns is empty (default)', () async {
    await service.assignResolvedBooks(
      schoolId: schoolId,
      classId: classId,
      studentId: studentId,
      teacherId: 'teacher1',
      books: [book()],
      targetDate: targetDate,
    );

    expect((await itemMetadata())?.containsKey('renewed'), false);
  });
}
