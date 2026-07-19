import 'server-only';

import { Timestamp, type Transaction } from 'firebase-admin/firestore';
import { adminDb } from '@/lib/firebase/admin';
import { lookupBookByIsbn } from './books';
import { normalizeIsbn, type AssignIsbnsResult } from './isbn-assignment';

export type DemoAllocationOrigin =
  | 'portal_isbn'
  | 'portal_allocation';

interface ExistingItem {
  id?: string;
  title?: string;
  bookId?: string;
  isbn?: string;
  isDeleted?: boolean;
}

function itemIsbn(item: ExistingItem): string | null {
  const direct = (item.isbn ?? '').trim();
  if (direct) return direct;
  const bookId = (item.bookId ?? '').trim();
  return bookId.startsWith('isbn_') ? bookId.slice(5).trim() || null : null;
}

async function assertCurrentLease(
  tx: Transaction,
  schoolId: string,
  generationId: string,
): Promise<void> {
  const reseedRef = adminDb.collection('demoAccess').doc('reseedStatus');
  const reseed = await tx.get(reseedRef);
  const data = reseed.data();
  if (
    data?.state !== 'succeeded' ||
    data?.schoolId !== schoolId ||
    data?.leaseId !== generationId
  ) {
    throw new Error('DEMO_GENERATION_EXPIRED');
  }
}

function isCurrentEphemeral(
  data: FirebaseFirestore.DocumentData | undefined,
  generationId: string,
): boolean {
  return data?.demoEphemeral === true && data?.demoGenerationId === generationId;
}

export async function assignDemoIsbnsToStudentWeek(
  schoolId: string,
  generationId: string,
  args: {
    studentId: string;
    classId: string;
    isbns: string[];
    weekStart: string;
    actorId: string;
    targetMinutes?: number;
  },
): Promise<AssignIsbnsResult> {
  const normalized: string[] = [];
  const invalid: string[] = [];
  for (const raw of args.isbns) {
    const value = normalizeIsbn(raw);
    if (value) normalized.push(value);
    else invalid.push(raw.trim());
  }

  // Resolve catalog metadata outside the transaction. cache:false guarantees
  // this demo-only operation cannot create school/community library records.
  const resolved = await Promise.all(
    [...new Set(normalized)].map(async (isbn) => ({
      isbn,
      book: await lookupBookByIsbn(isbn, schoolId, args.actorId, { cache: false }),
    })),
  );

  const stamp = args.weekStart.replace(/-/g, '');
  const allocationId = `demo_portal_isbn_${args.studentId}_${stamp}`;
  const allocationRef = adminDb
    .collection('schools').doc(schoolId)
    .collection('allocations').doc(allocationId);
  const [year, month, day] = args.weekStart.split('-').map(Number);
  const startDate = new Date(Date.UTC(year, (month ?? 1) - 1, day ?? 1));
  const endDate = new Date(startDate);
  endDate.setUTCDate(endDate.getUTCDate() + 6);
  endDate.setUTCHours(23, 59, 59, 999);

  return adminDb.runTransaction(async (tx) => {
    await assertCurrentLease(tx, schoolId, generationId);
    const snapshot = await tx.get(allocationRef);
    const existing = snapshot.data();
    if (snapshot.exists && !isCurrentEphemeral(existing, generationId)) {
      throw new Error('SEEDED_DEMO_ALLOCATION_IMMUTABLE');
    }

    const existingItems = Array.isArray(existing?.assignmentItems)
      ? existing!.assignmentItems as Record<string, unknown>[]
      : [];
    const activeIsbns = new Set(
      existingItems
        .filter((item) => item.isDeleted !== true)
        .map((item) => itemIsbn(item))
        .filter((value): value is string => Boolean(value)),
    );
    const usedIds = new Set(existingItems.map((item) => item.id).filter(Boolean));
    const assigned: { isbn: string; title: string }[] = [];
    const duplicates: string[] = [];
    const newItems: Record<string, unknown>[] = [];
    const now = Timestamp.now();

    for (const { isbn, book } of resolved) {
      if (activeIsbns.has(isbn)) {
        duplicates.push(isbn);
        continue;
      }
      let id = `isbn_${isbn}`;
      if (usedIds.has(id)) id = `isbn_${isbn}_${now.toMillis()}_${newItems.length}`;
      usedIds.add(id);
      activeIsbns.add(isbn);
      const title = book?.title?.trim() || 'Unrecognised Book';
      newItems.push({
        id,
        title,
        bookId: book?.id || `isbn_${isbn}`,
        isbn,
        isbnNormalized: isbn,
        isDeleted: false,
        addedAt: now,
        addedBy: args.actorId,
        metadata: { source: 'isbn_scan', resolvedFromCatalog: Boolean(book) },
      });
      assigned.push({ isbn, title });
    }

    const mergedItems = [...existingItems, ...newItems];
    const activeItems = mergedItems.filter((item) => item.isDeleted !== true);
    tx.set(allocationRef, {
      schoolId,
      classId: args.classId,
      teacherId: args.actorId,
      studentIds: [args.studentId],
      type: 'byTitle',
      cadence: 'weekly',
      targetMinutes: args.targetMinutes ?? 20,
      startDate: Timestamp.fromDate(startDate),
      endDate: Timestamp.fromDate(endDate),
      bookIds: activeItems.map((item) => item.bookId).filter(Boolean),
      bookTitles: activeItems.map((item) => item.title).filter(Boolean),
      assignmentItems: mergedItems,
      studentOverrides: {},
      schemaVersion: 2,
      isRecurring: false,
      isActive: true,
      createdAt: existing?.createdAt ?? now,
      createdBy: existing?.createdBy ?? args.actorId,
      demoEphemeral: true,
      demoGenerationId: generationId,
      demoOrigin: 'portal_isbn' satisfies DemoAllocationOrigin,
      metadata: {
        source: 'isbn_scan',
        scannedIsbns: [...activeIsbns],
        lastScanAt: now,
        lastScanBy: args.actorId,
      },
    }, { merge: true });

    return { allocationId, assigned, duplicates, invalid };
  });
}

export async function createDemoAllocation(
  schoolId: string,
  generationId: string,
  data: {
    classId: string;
    studentIds: string[];
    targetMinutes: number;
    startDate: string;
    endDate: string;
    assignmentItems: { title: string; bookId?: string; isbn?: string }[];
    actorId: string;
  },
): Promise<string> {
  const allocationRef = adminDb.collection('schools').doc(schoolId).collection('allocations').doc();
  const now = Timestamp.now();
  await adminDb.runTransaction(async (tx) => {
    await assertCurrentLease(tx, schoolId, generationId);
    tx.create(allocationRef, {
      schoolId,
      classId: data.classId,
      teacherId: data.actorId,
      studentIds: data.studentIds,
      type: 'byTitle',
      cadence: 'weekly',
      targetMinutes: data.targetMinutes,
      startDate: Timestamp.fromDate(new Date(data.startDate)),
      endDate: Timestamp.fromDate(new Date(data.endDate)),
      assignmentItems: data.assignmentItems.map((item, index) => ({
        id: `item_${allocationRef.id}_${index}`,
        title: item.title,
        bookId: item.bookId ?? null,
        isbn: item.isbn ?? null,
        isDeleted: false,
        addedAt: now,
        addedBy: data.actorId,
      })),
      studentOverrides: {},
      schemaVersion: 2,
      isRecurring: false,
      isActive: true,
      createdAt: now,
      createdBy: data.actorId,
      demoEphemeral: true,
      demoGenerationId: generationId,
      demoOrigin: 'portal_allocation' satisfies DemoAllocationOrigin,
      metadata: { allocationVersion: 1, lastOperation: 'create' },
    });
  });
  return allocationRef.id;
}

export async function deleteDemoAllocation(
  schoolId: string,
  generationId: string,
  allocationId: string,
): Promise<void> {
  const allocationRef = adminDb.collection('schools').doc(schoolId).collection('allocations').doc(allocationId);
  await adminDb.runTransaction(async (tx) => {
    await assertCurrentLease(tx, schoolId, generationId);
    const snapshot = await tx.get(allocationRef);
    if (!snapshot.exists) throw new Error('ALLOCATION_NOT_FOUND');
    if (!isCurrentEphemeral(snapshot.data(), generationId)) {
      throw new Error('SEEDED_DEMO_ALLOCATION_IMMUTABLE');
    }
    tx.delete(allocationRef);
  });
}
