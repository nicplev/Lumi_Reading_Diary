import { adminDb } from '@/lib/firebase/admin';
import type { LibraryAssignmentSnapshot, LibraryAssigneeStudent } from '@/lib/types';

/**
 * Server-side port of the app's `SchoolLibraryAssignmentService._buildSnapshot`
 * (lib/services/school_library_assignment_service.dart). Computes, from active
 * `byTitle` allocations within their date window + active students + classes,
 * the set of students assigned each book — keyed by bookId / ISBN / normalized
 * title. Reads raw allocation docs (not the serialized helper) so legacy
 * bookTitles/bookIds synthesis and `isbnNormalized` are honoured, matching the
 * allocation model's `effectiveAssignmentItemsForStudent`.
 */

type Raw = Record<string, unknown>;

interface Item {
  id: string;
  title: string;
  bookId?: string;
  isbn?: string;
  isDeleted: boolean;
}

function normalizeTitle(title: string): string {
  return title.trim().toLowerCase().replace(/\s+/g, ' ');
}

function isbnFromBookId(bookId?: string): string | undefined {
  const b = bookId?.trim();
  if (!b || !b.startsWith('isbn_')) return undefined;
  const isbn = b.substring(5).trim();
  return isbn || undefined;
}

function resolvedIsbn(item: Item): string | undefined {
  const raw = item.isbn?.trim();
  if (raw) return raw;
  return isbnFromBookId(item.bookId);
}

function dedupeKey(item: Item): string {
  const isbn = resolvedIsbn(item);
  if (isbn) return `isbn:${isbn.toLowerCase()}`;
  const bookId = item.bookId?.trim();
  if (bookId) return `book:${bookId}`;
  const nt = normalizeTitle(item.title);
  if (nt) return `title:${nt}`;
  return `item:${item.id}`;
}

function parseItem(raw: Raw, fallbackId: string): Item {
  const id = (raw.id as string | undefined)?.trim();
  const isbn = ((raw.isbnNormalized ?? raw.isbn) as string | undefined)?.trim();
  const bookId = (raw.bookId as string | undefined)?.trim();
  return {
    id: id && id.length > 0 ? id : fallbackId,
    title: ((raw.title as string | undefined) ?? '').trim(),
    bookId: bookId && bookId.length > 0 ? bookId : undefined,
    isbn: isbn && isbn.length > 0 ? isbn : undefined,
    isDeleted: raw.isDeleted === true,
  };
}

/** Legacy positional pairing of bookTitles/bookIds → items (mirrors `_legacyAssignmentItems`). */
function legacyItems(titles?: unknown, ids?: unknown): Item[] {
  const t = Array.isArray(titles) ? (titles as string[]) : [];
  const i = Array.isArray(ids) ? (ids as string[]) : [];
  const out: Item[] = [];
  for (let k = 0; k < t.length; k++) {
    const title = (t[k] ?? '').trim();
    if (!title) continue;
    const bookId = (k < i.length ? i[k]?.trim() : '') || undefined;
    out.push({ id: `legacy_${k}`, title, bookId, isbn: isbnFromBookId(bookId), isDeleted: false });
  }
  for (let k = t.length; k < i.length; k++) {
    const bookId = i[k]?.trim();
    if (!bookId) continue;
    const isbn = isbnFromBookId(bookId);
    out.push({
      id: `legacy_${k}`,
      title: isbn ? `Unknown Book (ISBN ${isbn})` : 'Unknown Book',
      bookId,
      isbn,
      isDeleted: false,
    });
  }
  return out;
}

function activeItems(data: Raw): Item[] {
  const rawItems = Array.isArray(data.assignmentItems) ? (data.assignmentItems as Raw[]) : [];
  let parsed = rawItems
    .filter((e) => e && typeof e === 'object')
    .map((e, i) => parseItem(e, `item_${i}`));
  if (parsed.length === 0) parsed = legacyItems(data.bookTitles, data.bookIds);
  return parsed.filter((it) => !it.isDeleted && it.title.trim().length > 0);
}

function effectiveItemsForStudent(data: Raw, studentId: string): Item[] {
  const base = activeItems(data);
  const overrides = data.studentOverrides as Raw | undefined;
  const ov = overrides?.[studentId] as Raw | undefined;
  if (!ov) return base;

  const removed = new Set(
    (Array.isArray(ov.removedItemIds) ? (ov.removedItemIds as string[]) : [])
      .map((s) => s?.trim())
      .filter((s): s is string => !!s)
  );
  const merged = base.filter((it) => !removed.has(it.id));
  const keys = new Set(merged.map(dedupeKey));

  const added = Array.isArray(ov.addedItems) ? (ov.addedItems as Raw[]) : [];
  added.forEach((e, i) => {
    if (!e || typeof e !== 'object') return;
    const item = parseItem(e, `override_${studentId}_${i}`);
    if (item.isDeleted || item.title.trim().length === 0) return;
    if (removed.has(item.id)) return;
    const k = dedupeKey(item);
    if (!keys.has(k)) {
      keys.add(k);
      merged.push(item);
    }
  });
  return merged;
}

function tsMillis(value: unknown): number | null {
  const v = value as { toDate?: () => Date } | undefined;
  const d = v?.toDate?.();
  return d ? d.getTime() : null;
}

export async function getLibraryAssignmentSnapshot(
  schoolId: string,
  viewerUid: string,
  viewerRole: 'teacher' | 'schoolAdmin'
): Promise<LibraryAssignmentSnapshot> {
  const emptyViewer = { role: viewerRole, classIds: [] as string[] };
  if (!schoolId) {
    return {
      studentIdsByBookId: {},
      studentIdsByIsbn: {},
      studentIdsByNormalizedTitle: {},
      students: {},
      viewer: emptyViewer,
    };
  }

  const schoolRef = adminDb.collection('schools').doc(schoolId);

  // Active students → membership + meta.
  const studentsSnap = await schoolRef.collection('students').where('isActive', '==', true).get();
  const activeStudentIds = new Set<string>();
  const studentIdsByClassId = new Map<string, Set<string>>();
  const studentMeta = new Map<string, { firstName: string; lastName: string; classId: string; characterId?: string }>();
  for (const doc of studentsSnap.docs) {
    const d = doc.data();
    const classId = (d.classId as string) ?? '';
    activeStudentIds.add(doc.id);
    if (!studentIdsByClassId.has(classId)) studentIdsByClassId.set(classId, new Set());
    studentIdsByClassId.get(classId)!.add(doc.id);
    studentMeta.set(doc.id, {
      firstName: (d.firstName as string) ?? '',
      lastName: (d.lastName as string) ?? '',
      classId,
      characterId: d.characterId as string | undefined,
    });
  }

  // Classes → names + the viewer's own classes (for the My-class filter).
  const classesSnap = await schoolRef.collection('classes').get();
  const classNameById = new Map<string, string>();
  const viewerClassIds: string[] = [];
  for (const doc of classesSnap.docs) {
    const d = doc.data();
    classNameById.set(doc.id, (d.name as string) ?? 'Unnamed Class');
    const teacherIds = Array.isArray(d.teacherIds) ? (d.teacherIds as string[]) : [];
    if (viewerRole === 'teacher' && d.isActive !== false && teacherIds.includes(viewerUid)) {
      viewerClassIds.push(doc.id);
    }
  }

  // Active allocations → index assigned students by bookId / ISBN / title.
  const allocSnap = await schoolRef.collection('allocations').where('isActive', '==', true).get();
  const now = Date.now();
  const byBookId: Record<string, Set<string>> = {};
  const byIsbn: Record<string, Set<string>> = {};
  const byTitle: Record<string, Set<string>> = {};
  const add = (map: Record<string, Set<string>>, key: string, sid: string) => {
    (map[key] ??= new Set()).add(sid);
  };

  for (const doc of allocSnap.docs) {
    const data = doc.data();
    if (data.type !== 'byTitle') continue;
    const start = tsMillis(data.startDate);
    const end = tsMillis(data.endDate);
    if (start === null || end === null) continue;
    if (start > now || end < now) continue; // inclusive window

    const studentIds = Array.isArray(data.studentIds) ? (data.studentIds as string[]) : [];
    const applicable =
      studentIds.length === 0
        ? [...(studentIdsByClassId.get((data.classId as string) ?? '') ?? new Set<string>())]
        : studentIds.filter((id) => activeStudentIds.has(id));

    for (const sid of applicable) {
      for (const item of effectiveItemsForStudent(data, sid)) {
        const bookId = item.bookId?.trim();
        if (bookId) add(byBookId, bookId, sid);
        const isbn = resolvedIsbn(item);
        if (isbn) add(byIsbn, isbn, sid);
        const nt = normalizeTitle(item.title);
        if (nt) add(byTitle, nt, sid);
      }
    }
  }

  // Directory of only the referenced students.
  const referenced = new Set<string>();
  for (const map of [byBookId, byIsbn, byTitle]) {
    for (const set of Object.values(map)) for (const id of set) referenced.add(id);
  }
  const students: Record<string, LibraryAssigneeStudent> = {};
  for (const id of referenced) {
    const meta = studentMeta.get(id);
    if (!meta) continue;
    students[id] = {
      id,
      firstName: meta.firstName,
      lastName: meta.lastName,
      classId: meta.classId,
      className: classNameById.get(meta.classId) ?? 'Unknown class',
      characterId: meta.characterId,
    };
  }

  const toArrays = (m: Record<string, Set<string>>) =>
    Object.fromEntries(Object.entries(m).map(([k, v]) => [k, [...v]]));

  return {
    studentIdsByBookId: toArrays(byBookId),
    studentIdsByIsbn: toArrays(byIsbn),
    studentIdsByNormalizedTitle: toArrays(byTitle),
    students,
    viewer: { role: viewerRole, classIds: viewerClassIds },
  };
}
