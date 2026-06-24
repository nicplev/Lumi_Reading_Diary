import { adminDb } from '@/lib/firebase/admin';
import { Timestamp } from 'firebase-admin/firestore';
import { lookupBookByIsbn } from './books';

// --- ISBN normalisation (mirrors the app's IsbnAssignmentService.normalizeIsbn:
// ISBN-10 is upgraded to ISBN-13, checksums validated, only 978/979 accepted) ---

function isValidIsbn10(s: string): boolean {
  if (!/^\d{9}[\dX]$/.test(s)) return false;
  let sum = 0;
  for (let i = 0; i < 10; i++) {
    const c = s[i];
    const v = c === 'X' ? 10 : Number(c);
    sum += v * (10 - i);
  }
  return sum % 11 === 0;
}

function isValidIsbn13(s: string): boolean {
  if (!/^\d{13}$/.test(s)) return false;
  let sum = 0;
  for (let i = 0; i < 13; i++) sum += Number(s[i]) * (i % 2 === 0 ? 1 : 3);
  return sum % 10 === 0;
}

function isbn10To13(s: string): string {
  const core = `978${s.slice(0, 9)}`;
  let sum = 0;
  for (let i = 0; i < 12; i++) sum += Number(core[i]) * (i % 2 === 0 ? 1 : 3);
  const check = (10 - (sum % 10)) % 10;
  return `${core}${check}`;
}

export function normalizeIsbn(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const cleaned = raw.toUpperCase().replace(/[^0-9X]/g, '');
  if (cleaned.length === 10) {
    if (!isValidIsbn10(cleaned)) return null;
    return isbn10To13(cleaned);
  }
  if (cleaned.length === 13 && isValidIsbn13(cleaned)) {
    if (cleaned.startsWith('978') || cleaned.startsWith('979')) return cleaned;
  }
  return null;
}

// --- Weekly allocation assignment (mirrors IsbnAssignmentService) ---

interface ExistingItem {
  id?: string;
  title?: string;
  bookId?: string;
  isbn?: string;
  isDeleted?: boolean;
}

function itemIsbn(i: ExistingItem): string | null {
  const x = (i.isbn ?? '').toString().trim();
  if (x) return x;
  const b = (i.bookId ?? '').toString().trim();
  if (b.startsWith('isbn_')) {
    const p = b.slice(5).trim();
    return p || null;
  }
  return null;
}

export interface AssignIsbnsResult {
  allocationId: string;
  assigned: { isbn: string; title: string }[];
  duplicates: string[];
  invalid: string[];
}

/**
 * Assigns books to a student's weekly allocation by ISBN — the web equivalent of
 * the app's ISBN scanner. Writes the SAME deterministic doc the scanner does:
 * `isbn_{studentId}_{YYYYMMDD-of-Monday}`, type byTitle / cadence weekly, so the
 * assignment is identical whether made here or scanned on an iPad.
 *
 * `weekStart` is the Monday as 'YYYY-MM-DD' computed in the caller's local time
 * (the browser, matching the app's device-local week) — it drives the doc id.
 */
export async function assignIsbnsToStudentWeek(
  schoolId: string,
  args: {
    studentId: string;
    classId: string;
    isbns: string[];
    weekStart: string; // 'YYYY-MM-DD' (Monday)
    actorId: string;
    targetMinutes?: number;
  }
): Promise<AssignIsbnsResult> {
  const stamp = args.weekStart.replace(/-/g, '');
  const allocationId = `isbn_${args.studentId}_${stamp}`;
  const ref = adminDb.collection('schools').doc(schoolId).collection('allocations').doc(allocationId);

  const [y, m, d] = args.weekStart.split('-').map(Number);
  const startDate = new Date(y, (m ?? 1) - 1, d ?? 1, 0, 0, 0, 0);
  const endDate = new Date(startDate);
  endDate.setDate(endDate.getDate() + 6);
  endDate.setHours(23, 59, 59, 999);

  const snap = await ref.get();
  const existing = snap.exists ? snap.data()! : null;
  const existingItems: Record<string, unknown>[] = (existing?.assignmentItems as Record<string, unknown>[]) ?? [];

  const activeIsbns = new Set(
    existingItems.filter((i) => !i.isDeleted).map((i) => itemIsbn(i)).filter((x): x is string => !!x)
  );
  const usedItemIds = new Set(existingItems.map((i) => i.id as string).filter(Boolean));

  const assigned: { isbn: string; title: string }[] = [];
  const duplicates: string[] = [];
  const invalid: string[] = [];
  const newItems: Record<string, unknown>[] = [];
  const now = Timestamp.now();

  for (const raw of args.isbns) {
    const isbn = normalizeIsbn(raw);
    if (!isbn) {
      invalid.push(raw.trim());
      continue;
    }
    if (activeIsbns.has(isbn)) {
      duplicates.push(isbn);
      continue;
    }

    const book = await lookupBookByIsbn(isbn, schoolId, args.actorId);
    const title = book?.title?.trim() || 'Unrecognised Book';

    let itemId = `isbn_${isbn}`;
    if (usedItemIds.has(itemId)) itemId = `isbn_${isbn}_${now.toMillis()}_${newItems.length}`;
    usedItemIds.add(itemId);
    activeIsbns.add(isbn);

    newItems.push({
      id: itemId,
      title,
      bookId: book?.id || `isbn_${isbn}`,
      isbn,
      isbnNormalized: isbn,
      isDeleted: false,
      addedAt: now,
      addedBy: args.actorId,
      metadata: { source: 'isbn_scan', resolvedFromCatalog: !!book },
    });
    assigned.push({ isbn, title });
  }

  const mergedItems = [...existingItems, ...newItems];
  const activeItems = mergedItems.filter((i) => !i.isDeleted);

  await ref.set(
    {
      schoolId,
      classId: args.classId,
      teacherId: args.actorId,
      studentIds: [args.studentId],
      type: 'byTitle',
      cadence: 'weekly',
      targetMinutes: args.targetMinutes ?? 20,
      startDate: Timestamp.fromDate(startDate),
      endDate: Timestamp.fromDate(endDate),
      bookIds: activeItems.map((i) => i.bookId).filter(Boolean),
      bookTitles: activeItems.map((i) => i.title).filter(Boolean),
      assignmentItems: mergedItems,
      schemaVersion: 2,
      isRecurring: false,
      isActive: true,
      createdAt: existing?.createdAt ?? now,
      createdBy: existing?.createdBy ?? args.actorId,
      metadata: {
        source: 'isbn_scan',
        scannedIsbns: [...activeIsbns],
        lastScanAt: now,
        lastScanBy: args.actorId,
      },
    },
    { merge: true }
  );

  return { allocationId, assigned, duplicates, invalid };
}
