import type { Firestore } from "firebase-admin/firestore";

// Retiring a book from a school's allocations.
//
// A book reference lives inside the `assignmentItems` array of maps on each
// allocation, which Firestore cannot query into. Deleting a book document
// without sweeping these leaves students holding an assignment that points at
// a title with no library entry.
//
// Retirement is a soft delete (isDeleted: true) rather than an array splice,
// matching AllocationCrudService.removeBookGlobally in the Flutter app.
// Readers filter on !isDeleted, so the book disappears for students
// immediately while the audit trail survives. Splicing would also shift the
// positional legacy ids (`legacy_<index>_<bookId>`) and orphan any per-student
// override that references them.

const ISBN_BOOK_ID_PREFIX = "isbn_";

// Firestore rejects batches over 500 writes; stay under it with headroom.
const ALLOCATION_BATCH_LIMIT = 400;

/** Identifies the book being removed. Either field alone is enough. */
export interface BookRemovalTarget {
  /** Normalized lowercase ISBN, when the book has one. */
  isbn?: string | null;
  /** The library document id, e.g. `isbn_9780141354828` or a school-local id. */
  bookId?: string | null;
}

export interface RemovalStamp {
  removedAt: Date;
  removedBy: string;
  /** Recorded on each retired item so the audit trail explains itself. */
  reason: string;
}

export function normalizeIsbn(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed.toLowerCase() : null;
}

// Mirrors AllocationBookItem.resolvedIsbn in
// lib/data/models/allocation_model.dart: prefer the explicit isbn field
// (isbnNormalized wins, as fromMap does), else derive it from an
// `isbn_<isbn>` bookId. Keep the two in step.
export function itemIsbn(item: Record<string, unknown>): string | null {
  const direct = normalizeIsbn(item.isbnNormalized ?? item.isbn);
  if (direct) return direct;
  const bookId = typeof item.bookId === "string" ? item.bookId.trim() : "";
  if (bookId.toLowerCase().startsWith(ISBN_BOOK_ID_PREFIX)) {
    return normalizeIsbn(bookId.slice(ISBN_BOOK_ID_PREFIX.length));
  }
  return null;
}

function itemMatches(
  item: Record<string, unknown>,
  target: BookRemovalTarget
): boolean {
  if (target.isbn) {
    const resolved = itemIsbn(item);
    if (resolved !== null && resolved === target.isbn) return true;
  }
  if (target.bookId) {
    const bookId = typeof item.bookId === "string" ? item.bookId.trim() : "";
    // Document ids are case-sensitive, so this comparison is exact.
    if (bookId.length > 0 && bookId === target.bookId) return true;
  }
  return false;
}

function slugify(value: string): string {
  const normalized = value.trim().toLowerCase().replace(/[^a-z0-9]+/g, "_");
  return normalized.length > 0 ? normalized : "book";
}

// Mirrors AllocationModel._legacyItemId. Ids must match what the Dart client
// derives, because per-student overrides reference items by id — regenerating
// them differently would orphan those references.
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

// Mirrors AllocationModel._legacyAssignmentItems: titles and ids pair
// positionally, with any trailing ids becoming "Unknown Book" entries.
export function materializeLegacyItems(
  bookTitles: unknown,
  bookIds: unknown
): Record<string, unknown>[] {
  const titles = Array.isArray(bookTitles) ? bookTitles : [];
  const ids = Array.isArray(bookIds) ? bookIds : [];
  const items: Record<string, unknown>[] = [];

  for (let i = 0; i < titles.length; i++) {
    const rawTitle = typeof titles[i] === "string" ? titles[i].trim() : "";
    if (rawTitle.length === 0) continue;
    const rawBookId =
      i < ids.length && typeof ids[i] === "string" ? ids[i].trim() : "";
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
    const rawBookId = typeof ids[i] === "string" ? ids[i].trim() : "";
    if (rawBookId.length === 0) continue;
    items.push({
      id: legacyItemId(i, "Unknown Book", rawBookId),
      title: "Unknown Book",
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
  stamp: RemovalStamp
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
        ...(typeof item.metadata === "object" && item.metadata !== null
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
  stamp: RemovalStamp
): Record<string, unknown> | null {
  if (!target.isbn && !target.bookId) return null;

  const rawItems = data.assignmentItems;
  const hasStructuredItems =
    Array.isArray(rawItems) &&
    rawItems.some((entry) => typeof entry === "object" && entry !== null);

  const baseItems = hasStructuredItems
    ? (rawItems as unknown[]).filter(
        (entry): entry is Record<string, unknown> =>
          typeof entry === "object" && entry !== null
      )
    : materializeLegacyItems(data.bookTitles, data.bookIds);

  const { items, changed } = markMatchingItems(baseItems, target, stamp);

  // Per-student overrides can add books the class allocation never had, so
  // they need the same sweep.
  let overridesChanged = false;
  const rawOverrides = data.studentOverrides;
  let nextOverrides: Record<string, unknown> | undefined;
  if (typeof rawOverrides === "object" && rawOverrides !== null) {
    nextOverrides = {};
    for (const [studentId, value] of Object.entries(
      rawOverrides as Record<string, unknown>
    )) {
      if (typeof value !== "object" || value === null) {
        nextOverrides[studentId] = value;
        continue;
      }
      const override = value as Record<string, unknown>;
      const added = Array.isArray(override.addedItems)
        ? (override.addedItems as unknown[]).filter(
            (entry): entry is Record<string, unknown> =>
              typeof entry === "object" && entry !== null
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

  // Recompute the legacy mirrors from the surviving items, matching
  // AllocationModel.syncLegacyBookFields / derivedBook*.
  const active = items.filter(
    (item) =>
      item.isDeleted !== true &&
      typeof item.title === "string" &&
      item.title.trim().length > 0
  );

  const update: Record<string, unknown> = {
    assignmentItems: items,
    bookTitles: active.map((item) => (item.title as string).trim()),
    bookIds: active
      .map((item) => (typeof item.bookId === "string" ? item.bookId.trim() : ""))
      .filter((id) => id.length > 0),
    schemaVersion: 2,
  };
  if (overridesChanged && nextOverrides) {
    update.studentOverrides = nextOverrides;
  }
  return update;
}

/**
 * Retires [target] from every allocation in one school. Returns the number of
 * allocations updated.
 *
 * Allocations cannot be queried by ISBN or bookId — the reference lives inside
 * an array of maps — so the school's allocations are scanned and filtered in
 * memory. Book deletion is a rare, human-initiated action, so the read cost is
 * acceptable; see docs/BOOK_DELETION_CASCADE.md for the indexed alternative.
 */
export async function cascadeBookRemovalForSchool(
  db: Firestore,
  schoolId: string,
  target: BookRemovalTarget,
  stamp: RemovalStamp
): Promise<number> {
  if (!target.isbn && !target.bookId) return 0;

  const allocationsSnap = await db
    .collection("schools").doc(schoolId)
    .collection("allocations").get();

  const pending = allocationsSnap.docs
    .map((allocationDoc) => ({
      ref: allocationDoc.ref,
      update: buildAllocationCascade(
        allocationDoc.data() as Record<string, unknown>,
        target,
        stamp
      ),
    }))
    .filter(
      (entry): entry is { ref: (typeof entry)["ref"]; update: Record<string, unknown> } =>
        entry.update !== null
    );

  for (let i = 0; i < pending.length; i += ALLOCATION_BATCH_LIMIT) {
    const chunk = pending.slice(i, i + ALLOCATION_BATCH_LIMIT);
    const batch = db.batch();
    for (const entry of chunk) {
      batch.update(entry.ref, entry.update);
    }
    await batch.commit();
  }

  return pending.length;
}
