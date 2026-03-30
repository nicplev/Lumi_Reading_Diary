import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/models/allocation_model.dart';

void main() {
  group('AllocationModel assignment items', () {
    test('builds active assignment items from legacy titles and ids', () {
      final model = AllocationModel(
        id: 'a1',
        schoolId: 's1',
        classId: 'c1',
        teacherId: 't1',
        studentIds: const <String>[],
        type: AllocationType.byTitle,
        cadence: AllocationCadence.weekly,
        targetMinutes: 20,
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 7),
        bookTitles: const ['Far Away', 'Little Bear'],
        bookIds: const ['isbn_9780123456786'],
        createdAt: DateTime(2026, 1, 1),
        createdBy: 't1',
      );

      final items = model.activeAssignmentItems;
      expect(items, hasLength(2));
      expect(items.first.title, 'Far Away');
      expect(items.first.bookId, 'isbn_9780123456786');
      expect(items.first.resolvedIsbn, '9780123456786');
      expect(items[1].title, 'Little Bear');
    });

    test('applies per-student override remove + add', () {
      final baseItems = <AllocationBookItem>[
        const AllocationBookItem(
          id: 'item_time',
          title: 'Time',
          bookId: 'isbn_9780000000001',
          isbn: '9780000000001',
        ),
        const AllocationBookItem(
          id: 'item_bear',
          title: 'Little Bear',
          bookId: 'isbn_9780000000002',
          isbn: '9780000000002',
        ),
      ];

      final override = StudentAllocationOverride(
        studentId: 'student_1',
        removedItemIds: const ['item_time'],
        addedItems: const [
          AllocationBookItem(
            id: 'override_item',
            title: 'Far Away',
            bookId: 'isbn_9780000000003',
            isbn: '9780000000003',
          ),
        ],
      );

      final model = AllocationModel(
        id: 'a2',
        schoolId: 's1',
        classId: 'c1',
        teacherId: 't1',
        studentIds: const <String>[],
        type: AllocationType.byTitle,
        cadence: AllocationCadence.weekly,
        targetMinutes: 20,
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 7),
        assignmentItems: baseItems,
        studentOverrides: {'student_1': override},
        schemaVersion: 2,
        createdAt: DateTime(2026, 1, 1),
        createdBy: 't1',
      );

      final effective = model.effectiveAssignmentItemsForStudent('student_1');
      expect(effective.map((i) => i.title), ['Little Bear', 'Far Away']);
      expect(effective.any((i) => i.id == 'item_time'), isFalse);
    });

    test('removedItemIds also hides previously added override items', () {
      final baseItems = <AllocationBookItem>[
        const AllocationBookItem(
          id: 'item_base',
          title: 'Base Book',
        ),
      ];

      final override = StudentAllocationOverride(
        studentId: 'student_1',
        removedItemIds: const ['override_item_1'],
        addedItems: const [
          AllocationBookItem(
            id: 'override_item_1',
            title: 'Student Override Book',
          ),
          AllocationBookItem(
            id: 'override_item_2',
            title: 'Still Visible Override Book',
          ),
        ],
      );

      final model = AllocationModel(
        id: 'a2b',
        schoolId: 's1',
        classId: 'c1',
        teacherId: 't1',
        studentIds: const <String>[],
        type: AllocationType.byTitle,
        cadence: AllocationCadence.weekly,
        targetMinutes: 20,
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 7),
        assignmentItems: baseItems,
        studentOverrides: {'student_1': override},
        schemaVersion: 2,
        createdAt: DateTime(2026, 1, 1),
        createdBy: 't1',
      );

      final effective = model.effectiveAssignmentItemsForStudent('student_1');
      expect(effective.map((i) => i.id), ['item_base', 'override_item_2']);
      expect(effective.any((i) => i.id == 'override_item_1'), isFalse);
    });

    test('syncLegacyBookFields derives legacy arrays from assignment items',
        () {
      final model = AllocationModel(
        id: 'a3',
        schoolId: 's1',
        classId: 'c1',
        teacherId: 't1',
        studentIds: const <String>[],
        type: AllocationType.byTitle,
        cadence: AllocationCadence.weekly,
        targetMinutes: 20,
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 7),
        assignmentItems: const [
          AllocationBookItem(
            id: 'i1',
            title: 'My Hungry Uncle',
            bookId: 'isbn_9780000000004',
          ),
          AllocationBookItem(
            id: 'i2',
            title: 'General',
            isDeleted: true,
          ),
        ],
        schemaVersion: 2,
        createdAt: DateTime(2026, 1, 1),
        createdBy: 't1',
      );

      final synced = model.syncLegacyBookFields();
      expect(synced.bookTitles, ['My Hungry Uncle']);
      expect(synced.bookIds, ['isbn_9780000000004']);
      expect(synced.schemaVersion, 2);
    });
  });
}
