import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/services/assert_writable.dart';
import '../data/models/allocation_model.dart';

/// Transaction-safe CRUD operations for allocation book items.
///
/// Supports:
/// - Global/class-level book item update, delete, swap
/// - Per-student overrides (remove/swap/add without mutating class baseline)
/// - Effective assignment resolution for a student
class AllocationCrudService {
  AllocationCrudService({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _allocations(String schoolId) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('allocations');
  }

  DocumentReference<Map<String, dynamic>> _allocationDoc({
    required String schoolId,
    required String allocationId,
  }) {
    return _allocations(schoolId).doc(allocationId);
  }

  Future<AllocationModel?> getAllocation({
    required String schoolId,
    required String allocationId,
  }) async {
    final doc = await _allocationDoc(
      schoolId: schoolId,
      allocationId: allocationId,
    ).get();
    if (!doc.exists) return null;
    return AllocationModel.fromFirestore(doc);
  }

  Future<AllocationModel> updateAllocation({
    required String schoolId,
    required String allocationId,
    required String actorId,
    AllocationType? type,
    AllocationCadence? cadence,
    int? targetMinutes,
    DateTime? startDate,
    DateTime? endDate,
    String? levelStart,
    String? levelEnd,
    bool? isRecurring,
    String? templateName,
    bool? isActive,
    List<String>? studentIds,
    List<AllocationBookItem>? assignmentItems,
  }) async {
    assertWritable(
      opLabel: 'allocation.updateAllocation',
      collection: 'allocations',
      docId: allocationId,
      operation: 'update',
    );
    final docRef = _allocationDoc(
      schoolId: schoolId,
      allocationId: allocationId,
    );
    final now = DateTime.now();

    return _firestore.runTransaction<AllocationModel>((txn) async {
      final snapshot = await txn.get(docRef);
      if (!snapshot.exists) {
        throw StateError('Allocation not found: $allocationId');
      }

      final existing = AllocationModel.fromFirestore(snapshot);
      final metadata = _nextMetadata(
        existingMetadata: existing.metadata,
        actorId: actorId,
        now: now,
        operation: 'update_allocation',
      );

      var updated = existing.copyWith(
        type: type ?? existing.type,
        cadence: cadence ?? existing.cadence,
        targetMinutes: targetMinutes ?? existing.targetMinutes,
        startDate: startDate ?? existing.startDate,
        endDate: endDate ?? existing.endDate,
        levelStart: levelStart ?? existing.levelStart,
        levelEnd: levelEnd ?? existing.levelEnd,
        isRecurring: isRecurring ?? existing.isRecurring,
        templateName: templateName ?? existing.templateName,
        isActive: isActive ?? existing.isActive,
        studentIds: studentIds ?? existing.studentIds,
        assignmentItems: assignmentItems ?? existing.assignmentItems,
        schemaVersion: 2,
        metadata: metadata,
      );

      updated = updated.syncLegacyBookFields();
      txn.set(docRef, updated.toFirestore(), SetOptions(merge: true));
      return updated;
    });
  }

  Future<AllocationBookItem> addBookGlobally({
    required String schoolId,
    required String allocationId,
    required String actorId,
    required String title,
    String? bookId,
    String? isbn,
    Map<String, dynamic>? metadata,
  }) async {
    assertWritable(
      opLabel: 'allocation.addBookGlobally',
      collection: 'allocations',
      docId: allocationId,
      operation: 'update',
    );
    final docRef = _allocationDoc(
      schoolId: schoolId,
      allocationId: allocationId,
    );
    final now = DateTime.now();
    final nextItem = AllocationBookItem(
      id: _newItemId(
        seed: title,
        suffix: now.millisecondsSinceEpoch.toString(),
      ),
      title: title.trim(),
      bookId: _clean(bookId),
      isbn: _clean(isbn),
      addedAt: now,
      addedBy: actorId,
      metadata: metadata,
    );

    return _firestore.runTransaction<AllocationBookItem>((txn) async {
      final snapshot = await txn.get(docRef);
      if (!snapshot.exists) {
        throw StateError('Allocation not found: $allocationId');
      }

      final existing = AllocationModel.fromFirestore(snapshot);
      final mergedItems = List<AllocationBookItem>.from(
          existing.assignmentItems ?? existing.activeAssignmentItems);
      final dedupe = mergedItems
          .where((item) => !item.isDeleted)
          .map((item) => item.dedupeKey)
          .toSet();
      if (dedupe.contains(nextItem.dedupeKey)) {
        return mergedItems
            .firstWhere((item) => item.dedupeKey == nextItem.dedupeKey);
      }

      mergedItems.add(nextItem);
      final updated = existing
          .copyWith(
            assignmentItems: mergedItems,
            schemaVersion: 2,
            metadata: _nextMetadata(
              existingMetadata: existing.metadata,
              actorId: actorId,
              now: now,
              operation: 'add_book_global',
            ),
          )
          .syncLegacyBookFields();

      txn.set(docRef, updated.toFirestore(), SetOptions(merge: true));
      return nextItem;
    });
  }

  Future<AllocationModel> updateBookGlobally({
    required String schoolId,
    required String allocationId,
    required String actorId,
    required String itemId,
    String? title,
    String? bookId,
    String? isbn,
    Map<String, dynamic>? metadata,
  }) async {
    final docRef = _allocationDoc(
      schoolId: schoolId,
      allocationId: allocationId,
    );
    final now = DateTime.now();

    return _firestore.runTransaction<AllocationModel>((txn) async {
      final snapshot = await txn.get(docRef);
      if (!snapshot.exists) {
        throw StateError('Allocation not found: $allocationId');
      }

      final existing = AllocationModel.fromFirestore(snapshot);
      final items = List<AllocationBookItem>.from(
          existing.assignmentItems ?? existing.activeAssignmentItems);
      final index = items.indexWhere((item) => item.id == itemId);
      if (index < 0) {
        throw StateError('Book item not found: $itemId');
      }

      items[index] = items[index].copyWith(
        title: title?.trim(),
        bookId: _clean(bookId),
        isbn: _clean(isbn),
        metadata: metadata ?? items[index].metadata,
      );

      final updated = existing
          .copyWith(
            assignmentItems: items,
            schemaVersion: 2,
            metadata: _nextMetadata(
              existingMetadata: existing.metadata,
              actorId: actorId,
              now: now,
              operation: 'update_book_global',
            ),
          )
          .syncLegacyBookFields();

      txn.set(docRef, updated.toFirestore(), SetOptions(merge: true));
      return updated;
    });
  }

  Future<AllocationModel> removeBookGlobally({
    required String schoolId,
    required String allocationId,
    required String actorId,
    required String itemId,
  }) async {
    final docRef = _allocationDoc(
      schoolId: schoolId,
      allocationId: allocationId,
    );
    final now = DateTime.now();

    return _firestore.runTransaction<AllocationModel>((txn) async {
      final snapshot = await txn.get(docRef);
      if (!snapshot.exists) {
        throw StateError('Allocation not found: $allocationId');
      }

      final existing = AllocationModel.fromFirestore(snapshot);
      final items = List<AllocationBookItem>.from(
          existing.assignmentItems ?? existing.activeAssignmentItems);
      final index = items.indexWhere((item) => item.id == itemId);
      if (index < 0) {
        throw StateError('Book item not found: $itemId');
      }

      if (!items[index].isDeleted) {
        items[index] = items[index].copyWith(
          isDeleted: true,
          metadata: {
            ...?items[index].metadata,
            'removedAt': Timestamp.fromDate(now),
            'removedBy': actorId,
          },
        );
      }

      final updated = existing
          .copyWith(
            assignmentItems: items,
            schemaVersion: 2,
            metadata: _nextMetadata(
              existingMetadata: existing.metadata,
              actorId: actorId,
              now: now,
              operation: 'remove_book_global',
            ),
          )
          .syncLegacyBookFields();

      txn.set(docRef, updated.toFirestore(), SetOptions(merge: true));
      return updated;
    });
  }

  Future<AllocationSwapResult> swapBookGlobally({
    required String schoolId,
    required String allocationId,
    required String actorId,
    required String removeItemId,
    required String nextTitle,
    String? nextBookId,
    String? nextIsbn,
    Map<String, dynamic>? nextMetadata,
  }) async {
    final docRef = _allocationDoc(
      schoolId: schoolId,
      allocationId: allocationId,
    );
    final now = DateTime.now();

    return _firestore.runTransaction<AllocationSwapResult>((txn) async {
      final snapshot = await txn.get(docRef);
      if (!snapshot.exists) {
        throw StateError('Allocation not found: $allocationId');
      }

      final existing = AllocationModel.fromFirestore(snapshot);
      final items = List<AllocationBookItem>.from(
          existing.assignmentItems ?? existing.activeAssignmentItems);
      final removeIndex = items.indexWhere((item) => item.id == removeItemId);
      if (removeIndex < 0) {
        throw StateError('Book item not found: $removeItemId');
      }

      items[removeIndex] = items[removeIndex].copyWith(
        isDeleted: true,
        metadata: {
          ...?items[removeIndex].metadata,
          'swappedOutAt': Timestamp.fromDate(now),
          'swappedOutBy': actorId,
        },
      );

      final addedItem = AllocationBookItem(
        id: _newItemId(
          seed: nextTitle,
          suffix: now.millisecondsSinceEpoch.toString(),
        ),
        title: nextTitle.trim(),
        bookId: _clean(nextBookId),
        isbn: _clean(nextIsbn),
        addedAt: now,
        addedBy: actorId,
        metadata: nextMetadata,
      );
      items.add(addedItem);

      final updated = existing
          .copyWith(
            assignmentItems: items,
            schemaVersion: 2,
            metadata: _nextMetadata(
              existingMetadata: existing.metadata,
              actorId: actorId,
              now: now,
              operation: 'swap_book_global',
            ),
          )
          .syncLegacyBookFields();

      txn.set(docRef, updated.toFirestore(), SetOptions(merge: true));
      return AllocationSwapResult(
        removedItemId: removeItemId,
        addedItem: addedItem,
        updatedAllocation: updated,
      );
    });
  }

  Future<AllocationModel> removeBookForStudents({
    required String schoolId,
    required String allocationId,
    required String actorId,
    required String itemId,
    required List<String> studentIds,
  }) async {
    return _updateStudentOverrides(
      schoolId: schoolId,
      allocationId: allocationId,
      actorId: actorId,
      operation: 'remove_book_student_override',
      mutate: (existing) {
        final now = DateTime.now();
        final overrides = Map<String, StudentAllocationOverride>.from(
          existing.studentOverrides ??
              const <String, StudentAllocationOverride>{},
        );

        for (final studentId
            in studentIds.map((id) => id.trim()).where((id) => id.isNotEmpty)) {
          final current = overrides[studentId] ??
              StudentAllocationOverride(studentId: studentId);
          final removed = {...current.removedItemIds, itemId}.toList();
          removed.sort();

          overrides[studentId] = current.copyWith(
            removedItemIds: removed,
            updatedAt: now,
            updatedBy: actorId,
          );
        }
        return existing.copyWith(
          studentOverrides: overrides,
          schemaVersion: 2,
        );
      },
    );
  }

  Future<AllocationModel> swapBookForStudents({
    required String schoolId,
    required String allocationId,
    required String actorId,
    required String removeItemId,
    required List<String> studentIds,
    required String nextTitle,
    String? nextBookId,
    String? nextIsbn,
    Map<String, dynamic>? nextMetadata,
  }) async {
    return _updateStudentOverrides(
      schoolId: schoolId,
      allocationId: allocationId,
      actorId: actorId,
      operation: 'swap_book_student_override',
      mutate: (existing) {
        final now = DateTime.now();
        final overrides = Map<String, StudentAllocationOverride>.from(
          existing.studentOverrides ??
              const <String, StudentAllocationOverride>{},
        );

        for (final studentId
            in studentIds.map((id) => id.trim()).where((id) => id.isNotEmpty)) {
          final current = overrides[studentId] ??
              StudentAllocationOverride(studentId: studentId);
          final removed = {...current.removedItemIds, removeItemId}.toList();
          removed.sort();

          final addedItems = List<AllocationBookItem>.from(current.addedItems)
            ..add(
              AllocationBookItem(
                id: _newItemId(
                  seed: nextTitle,
                  suffix: '${studentId}_${now.millisecondsSinceEpoch}',
                ),
                title: nextTitle.trim(),
                bookId: _clean(nextBookId),
                isbn: _clean(nextIsbn),
                addedAt: now,
                addedBy: actorId,
                metadata: nextMetadata,
              ),
            );

          overrides[studentId] = current.copyWith(
            removedItemIds: removed,
            addedItems: addedItems,
            updatedAt: now,
            updatedBy: actorId,
          );
        }

        return existing.copyWith(
          studentOverrides: overrides,
          schemaVersion: 2,
        );
      },
    );
  }

  EffectiveStudentAllocation resolveEffectiveAllocationForStudent({
    required AllocationModel allocation,
    required String studentId,
  }) {
    final items = allocation.effectiveAssignmentItemsForStudent(studentId);
    final hasOverride =
        allocation.studentOverrides?.containsKey(studentId) == true;
    return EffectiveStudentAllocation(
      allocationId: allocation.id,
      studentId: studentId,
      items: items,
      hasOverride: hasOverride,
    );
  }

  Future<AllocationModel> _updateStudentOverrides({
    required String schoolId,
    required String allocationId,
    required String actorId,
    required String operation,
    required AllocationModel Function(AllocationModel existing) mutate,
  }) async {
    final docRef = _allocationDoc(
      schoolId: schoolId,
      allocationId: allocationId,
    );

    return _firestore.runTransaction<AllocationModel>((txn) async {
      final snapshot = await txn.get(docRef);
      if (!snapshot.exists) {
        throw StateError('Allocation not found: $allocationId');
      }

      final existing = AllocationModel.fromFirestore(snapshot);
      final now = DateTime.now();
      final mutated = mutate(existing);
      final updated = mutated.copyWith(
        metadata: _nextMetadata(
          existingMetadata: existing.metadata,
          actorId: actorId,
          now: now,
          operation: operation,
        ),
      );

      txn.set(docRef, updated.toFirestore(), SetOptions(merge: true));
      return updated;
    });
  }

  Map<String, dynamic> _nextMetadata({
    required Map<String, dynamic>? existingMetadata,
    required String actorId,
    required DateTime now,
    required String operation,
  }) {
    final nextVersion =
        ((existingMetadata?['allocationVersion'] as num?)?.toInt() ?? 0) + 1;
    return {
      ...?existingMetadata,
      'allocationVersion': nextVersion,
      'lastModifiedBy': actorId,
      'lastModifiedAt': Timestamp.fromDate(now),
      'lastOperation': operation,
    };
  }

  String _newItemId({
    required String seed,
    required String suffix,
  }) {
    final slug = seed
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final safeSlug = slug.isEmpty ? 'book' : slug;
    return 'item_${safeSlug}_$suffix';
  }

  String? _clean(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}

class AllocationSwapResult {
  const AllocationSwapResult({
    required this.removedItemId,
    required this.addedItem,
    required this.updatedAllocation,
  });

  final String removedItemId;
  final AllocationBookItem addedItem;
  final AllocationModel updatedAllocation;
}

class EffectiveStudentAllocation {
  const EffectiveStudentAllocation({
    required this.allocationId,
    required this.studentId,
    required this.items,
    required this.hasOverride,
  });

  final String allocationId;
  final String studentId;
  final List<AllocationBookItem> items;
  final bool hasOverride;
}
