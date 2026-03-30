import { adminDb } from '@/lib/firebase/admin';
import { FieldValue } from 'firebase-admin/firestore';
import type { Allocation, AllocationBookItem } from '@/lib/types';

export async function addStudentOverride(
  schoolId: string,
  allocationId: string,
  studentId: string,
  override: { removedItemIds?: string[]; addedItems?: { title: string; bookId?: string; isbn?: string }[] },
  actorId: string
): Promise<void> {
  const ref = adminDb.collection('schools').doc(schoolId).collection('allocations').doc(allocationId);
  const doc = await ref.get();
  if (!doc.exists) throw new Error('Allocation not found');

  const existing = (doc.data()!.studentOverrides?.[studentId] ?? {
    removedItemIds: [],
    addedItems: [],
  }) as { removedItemIds: string[]; addedItems: Record<string, unknown>[] };

  const removedItemIds = [
    ...new Set([...existing.removedItemIds, ...(override.removedItemIds ?? [])]),
  ];

  const addedItems = [
    ...existing.addedItems,
    ...(override.addedItems ?? []).map((item) => ({
      id: `override_${studentId}_${Date.now()}`,
      title: item.title,
      bookId: item.bookId ?? null,
      isbn: item.isbn ?? null,
      isDeleted: false,
      addedAt: new Date().toISOString(),
      addedBy: actorId,
    })),
  ];

  await ref.update({
    [`studentOverrides.${studentId}`]: {
      studentId,
      removedItemIds,
      addedItems,
      updatedAt: new Date(),
      updatedBy: actorId,
    },
    'metadata.lastModifiedBy': actorId,
    'metadata.lastModifiedAt': new Date().toISOString(),
    'metadata.lastOperation': 'studentOverride',
    'metadata.allocationVersion': FieldValue.increment(1),
  });
}

export async function removeStudentOverride(
  schoolId: string,
  allocationId: string,
  studentId: string,
  itemId: string,
  actorId: string
): Promise<void> {
  await addStudentOverride(schoolId, allocationId, studentId, { removedItemIds: [itemId] }, actorId);
}

export function resolveEffectiveItems(allocation: Allocation, studentId: string): AllocationBookItem[] {
  const baseItems = (allocation.assignmentItems ?? []).filter((item) => !item.isDeleted);
  const override = allocation.studentOverrides?.[studentId];

  if (!override) return baseItems;

  // Remove items that are in the student's removedItemIds
  const afterRemoval = baseItems.filter((item) => !override.removedItemIds.includes(item.id));

  // Add student-specific items
  const addedItems = override.addedItems.filter((item) => !item.isDeleted);

  // Deduplicate by id
  const seen = new Set<string>();
  const result: AllocationBookItem[] = [];
  for (const item of [...afterRemoval, ...addedItems]) {
    if (!seen.has(item.id)) {
      seen.add(item.id);
      result.push(item);
    }
  }

  return result;
}
