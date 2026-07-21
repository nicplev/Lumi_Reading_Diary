// Retiring a book from a school's allocations — pure logic.
//
// NOTE: school-admin-web is intentionally outside the pnpm workspace and
// cannot use @lumi/server-ops, so this MIRRORS
// packages/server-ops/src/allocationCascade.ts. The two are held in step by
// packages/server-ops/test/allocationCascade.parity.test.ts — if you change
// one, change the other or that test fails.
//
// This module deliberately imports nothing from firebase-admin so the parity
// test can load it without the `@/` alias or Admin SDK credentials. The
// Firestore scan that applies these updates lives in books.ts.
//
// A book reference lives inside the `assignmentItems` array of maps on each
// allocation, which Firestore cannot query into. Deleting a book document
// without sweeping these leaves students holding an assignment that points at
// a title with no library entry.
//
// Retirement is a soft delete (isDeleted: true) rather than an array splice,
// matching AllocationCrudService.removeBookGlobally in the Flutter app.
// Readers filter on !isDeleted. Splicing would also shift the positional
// legacy ids (`legacy_<index>_<bookId>`) and orphan per-student overrides.

const ISBN_BOOK_ID_PREFIX = 'isbn_';

/** Identifies the book being removed. Either field alone is enough. */
export interface BookRemovalTarget {
  isbn?: string | null;
  bookId?: string | null;
}

export interface RemovalStamp {
  removedAt: Date;
  removedBy: string;
  reason: string;
}

export function normalizeCascadeIsbn(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed.toLowerCase() : null;
}

// Mirrors AllocationBookItem.resolvedIsbn in
// lib/data/models/allocation_model.dart.
export function itemIsbn(item: Record<string, unknown>): string | null {
  const direct = normalizeCascadeIsbn(item.isbnNormalized ?? item.isbn);
  if (direct) return direct;
  const bookId = typeof item.bookId === 'string' ? item.bookId.trim() : '';
  if (bookId.toLowerCase().startsWith(ISBN_BOOK_ID_PREFIX)) {
    return normalizeCascadeIsbn(bookId.slice(ISBN_BOOK_ID_PREFIX.length));
  }
  return null;
}

function itemMatches(
  item: Record<string, unknown>,
  target: BookRemovalTarget,
): boolean {
  if (target.isbn) {
    const resolved = itemIsbn(item);
    if (resolved !== null && resolved === target.isbn) return true;
  }
  if (target.bookId) {
    const bookId = typeof item.bookId === 'string' ? item.bookId.trim() : '';
    // Document ids are case-sensitive, so this comparison is exact.
    if (bookId.length > 0 && bookId === target.bookId) return true;
  }
  return false;
}

function slugify(value: string): string {
  const normalized = value.trim().toLowerCase().replace(/[^a-z0-9]+/g, '_');
  return normalized.length > 0 ? normalized : 'book';
}

// Mirrors AllocationModel._legacyItemId.
function legacyItemId(index: number, title: string, bookId?: string): string {
  const idPart = bookId && bookId.length > 0 ? bookId : slugify(title);
  return `legacy_${index}_${idPart}`;
}

function isbnFromBookId(bookId: string | null): string | null {
  if (!bookId) return null;
  if (!bookId.startsWith(ISBN_BOOK_ID_PREFIX)) return null;
  const parsed = bookId.slice(ISBN_BOOK_ID_PREFIX.length).trim();
  return parsed.length > 0 ? parsed : null;
}

// Mirrors AllocationModel._legacyAssignmentItems.
export function materializeLegacyItems(
  bookTitles: unknown,
  bookIds: unknown,
): Record<string, unknown>[] {
  const titles = Array.isArray(bookTitles) ? bookTitles : [];
  const ids = Array.isArray(bookIds) ? bookIds : [];
  const items: Record<string, unknown>[] = [];

  for (let i = 0; i < titles.length; i++) {
    const rawTitle = typeof titles[i] === 'string' ? titles[i].trim() : '';
    if (rawTitle.length === 0) continue;
    const rawBookId =
      i < ids.length && typeof ids[i] === 'string' ? ids[i].trim() : '';
    const resolvedBookId = rawBookId.length > 0 ? rawBookId : null;
    items.push({
      id: legacyItemId(i, rawTitle, resolvedBookId ?? undefined),
      title: rawTitle,
      bookId: resolvedBookId,
      isbn: isbnFromBookId(resolvedBookId),
      isDeleted: false,
    });
  }

  for (let i = titles.length; i < ids.length; i++) {
    const rawBookId = typeof ids[i] === 'string' ? ids[i].trim() : '';
    if (rawBookId.length === 0) continue;
    items.push({
      id: legacyItemId(i, 'Unknown Book', rawBookId),
      title: 'Unknown Book',
      bookId: rawBookId,
      isbn: isbnFromBookId(rawBookId),
      isDeleted: false,
    });
  }

  return items;
}

function markMatchingItems(
  items: Record<string, unknown>[],
  target: BookRemovalTarget,
  stamp: RemovalStamp,
): { items: Record<string, unknown>[]; changed: boolean } {
  let changed = false;
  const next = items.map((item) => {
    if (item.isDeleted === true) return item;
    if (!itemMatches(item, target)) return item;
    changed = true;
    return {
      ...item,
      isDeleted: true,
      metadata: {
        ...(typeof item.metadata === 'object' && item.metadata !== null
          ? (item.metadata as Record<string, unknown>)
          : {}),
        removedAt: stamp.removedAt,
        removedBy: stamp.removedBy,
        removedReason: stamp.reason,
      },
    };
  });
  return { items: next, changed };
}

/**
 * Builds the update payload that retires every reference to [target] in one
 * allocation, or null when the allocation never referenced the book.
 */
export function buildAllocationCascade(
  data: Record<string, unknown>,
  target: BookRemovalTarget,
  stamp: RemovalStamp,
): Record<string, unknown> | null {
  if (!target.isbn && !target.bookId) return null;

  const rawItems = data.assignmentItems;
  const hasStructuredItems =
    Array.isArray(rawItems) &&
    rawItems.some((entry) => typeof entry === 'object' && entry !== null);

  const baseItems = hasStructuredItems
    ? (rawItems as unknown[]).filter(
        (entry): entry is Record<string, unknown> =>
          typeof entry === 'object' && entry !== null,
      )
    : materializeLegacyItems(data.bookTitles, data.bookIds);

  const { items, changed } = markMatchingItems(baseItems, target, stamp);

  // Per-student overrides can add books the class allocation never had.
  let overridesChanged = false;
  const rawOverrides = data.studentOverrides;
  let nextOverrides: Record<string, unknown> | undefined;
  if (typeof rawOverrides === 'object' && rawOverrides !== null) {
    nextOverrides = {};
    for (const [studentId, value] of Object.entries(
      rawOverrides as Record<string, unknown>,
    )) {
      if (typeof value !== 'object' || value === null) {
        nextOverrides[studentId] = value;
        continue;
      }
      const override = value as Record<string, unknown>;
      const added = Array.isArray(override.addedItems)
        ? (override.addedItems as unknown[]).filter(
            (entry): entry is Record<string, unknown> =>
              typeof entry === 'object' && entry !== null,
          )
        : [];
      if (added.length === 0) {
        nextOverrides[studentId] = override;
        continue;
      }
      const marked = markMatchingItems(added, target, stamp);
      if (!marked.changed) {
        nextOverrides[studentId] = override;
        continue;
      }
      overridesChanged = true;
      nextOverrides[studentId] = { ...override, addedItems: marked.items };
    }
  }

  if (!changed && !overridesChanged) return null;

  // Recompute the legacy mirrors, matching
  // AllocationModel.syncLegacyBookFields / derivedBook*.
  const active = items.filter(
    (item) =>
      item.isDeleted !== true &&
      typeof item.title === 'string' &&
      item.title.trim().length > 0,
  );

  const update: Record<string, unknown> = {
    assignmentItems: items,
    bookTitles: active.map((item) => (item.title as string).trim()),
    bookIds: active
      .map((item) => (typeof item.bookId === 'string' ? item.bookId.trim() : ''))
      .filter((id) => id.length > 0),
    schemaVersion: 2,
  };
  if (overridesChanged && nextOverrides) {
    update.studentOverrides = nextOverrides;
  }
  return update;
}
