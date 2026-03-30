import { adminDb } from '@/lib/firebase/admin';
import { FieldValue } from 'firebase-admin/firestore';
import type { Allocation, AllocationBookItem } from '@/lib/types';

function toAllocation(doc: FirebaseFirestore.DocumentSnapshot): Allocation {
  const data = doc.data()!;
  return {
    id: doc.id,
    schoolId: data.schoolId ?? '',
    classId: data.classId ?? '',
    teacherId: data.teacherId ?? '',
    studentIds: data.studentIds ?? [],
    type: data.type ?? 'byTitle',
    cadence: data.cadence ?? 'weekly',
    targetMinutes: data.targetMinutes ?? 15,
    startDate: data.startDate?.toDate() ?? new Date(),
    endDate: data.endDate?.toDate() ?? new Date(),
    levelStart: data.levelStart,
    levelEnd: data.levelEnd,
    bookIds: data.bookIds,
    bookTitles: data.bookTitles,
    assignmentItems: (data.assignmentItems ?? []).map(toBookItem),
    studentOverrides: toOverridesMap(data.studentOverrides),
    schemaVersion: data.schemaVersion ?? 2,
    isRecurring: data.isRecurring ?? false,
    templateName: data.templateName,
    isActive: data.isActive ?? true,
    createdAt: data.createdAt?.toDate() ?? new Date(),
    createdBy: data.createdBy ?? '',
    metadata: data.metadata,
  };
}

function toBookItem(raw: Record<string, unknown>): AllocationBookItem {
  return {
    id: (raw.id as string) ?? '',
    title: (raw.title as string) ?? '',
    bookId: raw.bookId as string | undefined,
    isbn: raw.isbn as string | undefined,
    isDeleted: (raw.isDeleted as boolean) ?? false,
    addedAt: (raw.addedAt as { toDate?: () => Date })?.toDate?.() ?? undefined,
    addedBy: raw.addedBy as string | undefined,
    metadata: raw.metadata as Record<string, unknown> | undefined,
  };
}

function toOverridesMap(
  raw: Record<string, unknown> | undefined
): Record<string, { studentId: string; removedItemIds: string[]; addedItems: AllocationBookItem[]; updatedAt?: Date; updatedBy?: string }> | undefined {
  if (!raw) return undefined;
  const result: Record<string, { studentId: string; removedItemIds: string[]; addedItems: AllocationBookItem[]; updatedAt?: Date; updatedBy?: string }> = {};
  for (const [studentId, value] of Object.entries(raw)) {
    const v = value as Record<string, unknown>;
    result[studentId] = {
      studentId,
      removedItemIds: (v.removedItemIds as string[]) ?? [],
      addedItems: ((v.addedItems as Record<string, unknown>[]) ?? []).map(toBookItem),
      updatedAt: (v.updatedAt as { toDate?: () => Date })?.toDate?.(),
      updatedBy: v.updatedBy as string | undefined,
    };
  }
  return result;
}

export async function getAllocations(
  schoolId: string,
  filters?: { classId?: string; isActive?: boolean }
): Promise<Allocation[]> {
  let query: FirebaseFirestore.Query = adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('allocations');

  if (filters?.classId) {
    query = query.where('classId', '==', filters.classId);
  }
  if (filters?.isActive !== undefined) {
    query = query.where('isActive', '==', filters.isActive);
  }

  const snap = await query.get();
  return snap.docs.map(toAllocation);
}

export async function getAllocation(schoolId: string, allocationId: string): Promise<Allocation | null> {
  const doc = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('allocations')
    .doc(allocationId)
    .get();
  if (!doc.exists) return null;
  return toAllocation(doc);
}

export async function createAllocation(
  schoolId: string,
  data: {
    classId: string;
    teacherId: string;
    studentIds?: string[];
    type: string;
    cadence: string;
    targetMinutes: number;
    startDate: string;
    endDate: string;
    levelStart?: string;
    levelEnd?: string;
    assignmentItems?: { title: string; bookId?: string; isbn?: string }[];
    createdBy: string;
  }
): Promise<string> {
  const ref = adminDb.collection('schools').doc(schoolId).collection('allocations').doc();
  const now = FieldValue.serverTimestamp();

  const items: Record<string, unknown>[] = (data.assignmentItems ?? []).map((item, i) => ({
    id: `item_${ref.id}_${i}`,
    title: item.title,
    bookId: item.bookId ?? null,
    isbn: item.isbn ?? null,
    isDeleted: false,
    addedAt: new Date().toISOString(),
    addedBy: data.createdBy,
  }));

  await ref.set({
    schoolId,
    classId: data.classId,
    teacherId: data.teacherId,
    studentIds: data.studentIds ?? [],
    type: data.type,
    cadence: data.cadence,
    targetMinutes: data.targetMinutes,
    startDate: new Date(data.startDate),
    endDate: new Date(data.endDate),
    levelStart: data.levelStart ?? null,
    levelEnd: data.levelEnd ?? null,
    assignmentItems: items,
    studentOverrides: {},
    schemaVersion: 2,
    isRecurring: false,
    isActive: true,
    createdAt: now,
    createdBy: data.createdBy,
    metadata: {
      allocationVersion: 1,
      lastModifiedBy: data.createdBy,
      lastModifiedAt: new Date().toISOString(),
      lastOperation: 'create',
    },
  });

  return ref.id;
}

export async function updateAllocation(
  schoolId: string,
  allocationId: string,
  data: Partial<Pick<Allocation, 'cadence' | 'targetMinutes' | 'type' | 'levelStart' | 'levelEnd'>> & {
    startDate?: string;
    endDate?: string;
    studentIds?: string[];
    updatedBy: string;
  }
): Promise<void> {
  const update: Record<string, unknown> = {};
  if (data.cadence !== undefined) update.cadence = data.cadence;
  if (data.targetMinutes !== undefined) update.targetMinutes = data.targetMinutes;
  if (data.type !== undefined) update.type = data.type;
  if (data.levelStart !== undefined) update.levelStart = data.levelStart;
  if (data.levelEnd !== undefined) update.levelEnd = data.levelEnd;
  if (data.startDate !== undefined) update.startDate = new Date(data.startDate);
  if (data.endDate !== undefined) update.endDate = new Date(data.endDate);
  if (data.studentIds !== undefined) update.studentIds = data.studentIds;

  update['metadata.lastModifiedBy'] = data.updatedBy;
  update['metadata.lastModifiedAt'] = new Date().toISOString();
  update['metadata.lastOperation'] = 'update';
  update['metadata.allocationVersion'] = FieldValue.increment(1);

  await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('allocations')
    .doc(allocationId)
    .update(update);
}

export async function deactivateAllocation(schoolId: string, allocationId: string): Promise<void> {
  await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('allocations')
    .doc(allocationId)
    .update({ isActive: false });
}

export async function addBookToAllocation(
  schoolId: string,
  allocationId: string,
  item: { title: string; bookId?: string; isbn?: string },
  actorId: string
): Promise<void> {
  const ref = adminDb.collection('schools').doc(schoolId).collection('allocations').doc(allocationId);
  const doc = await ref.get();
  if (!doc.exists) throw new Error('Allocation not found');

  const existing = (doc.data()!.assignmentItems ?? []) as Record<string, unknown>[];
  const dedupeKey = item.bookId || item.isbn || item.title.toLowerCase().trim();
  const isDuplicate = existing.some((e) => {
    if (e.isDeleted) return false;
    const eKey = (e.bookId as string) || (e.isbn as string) || (e.title as string || '').toLowerCase().trim();
    return eKey === dedupeKey;
  });
  if (isDuplicate) return;

  const newItem = {
    id: `item_${allocationId}_${Date.now()}`,
    title: item.title,
    bookId: item.bookId ?? null,
    isbn: item.isbn ?? null,
    isDeleted: false,
    addedAt: new Date().toISOString(),
    addedBy: actorId,
  };

  await ref.update({
    assignmentItems: FieldValue.arrayUnion(newItem),
    'metadata.lastModifiedBy': actorId,
    'metadata.lastModifiedAt': new Date().toISOString(),
    'metadata.lastOperation': 'addBook',
    'metadata.allocationVersion': FieldValue.increment(1),
  });
}

export async function removeBookFromAllocation(
  schoolId: string,
  allocationId: string,
  itemId: string,
  actorId: string
): Promise<void> {
  const ref = adminDb.collection('schools').doc(schoolId).collection('allocations').doc(allocationId);
  const doc = await ref.get();
  if (!doc.exists) throw new Error('Allocation not found');

  const items = (doc.data()!.assignmentItems ?? []) as Record<string, unknown>[];
  const updated = items.map((item) => {
    if (item.id === itemId) {
      return { ...item, isDeleted: true, metadata: { ...(item.metadata as Record<string, unknown>), deletedBy: actorId, deletedAt: new Date().toISOString() } };
    }
    return item;
  });

  await ref.update({
    assignmentItems: updated,
    'metadata.lastModifiedBy': actorId,
    'metadata.lastModifiedAt': new Date().toISOString(),
    'metadata.lastOperation': 'removeBook',
    'metadata.allocationVersion': FieldValue.increment(1),
  });
}

export async function getStudentAllocations(schoolId: string, studentId: string, classId: string): Promise<Allocation[]> {
  // Get allocations for the student's class that are active
  const classAllocations = await getAllocations(schoolId, { classId, isActive: true });

  const now = new Date();
  return classAllocations.filter((a) => {
    // Whole class (empty studentIds) or student specifically included
    const isTargeted = a.studentIds.length === 0 || a.studentIds.includes(studentId);
    // Within date range
    const inRange = a.startDate <= now && a.endDate >= now;
    return isTargeted && inRange;
  });
}
