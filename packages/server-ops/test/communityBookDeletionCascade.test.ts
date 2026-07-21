import test from "node:test";
import assert from "node:assert/strict";
import { buildAllocationCascade } from "../src/allocationCascade";

const STAMP = {
  removedAt: new Date("2026-07-21T00:00:00Z"),
  removedBy: "admin1",
  reason: "community_book_deleted",
};
const ISBN = "9780141354828";

test("retires a structured item matched on the isbn field", () => {
  const update = buildAllocationCascade(
    {
      assignmentItems: [
        { id: "a", title: "Matilda", isbn: ISBN, isDeleted: false },
        { id: "b", title: "The BFG", isbn: "9780141365404", isDeleted: false },
      ],
      bookTitles: ["Matilda", "The BFG"],
      bookIds: [],
    },
    { isbn: ISBN },
    STAMP
  );

  assert.ok(update);
  const items = update.assignmentItems as Record<string, unknown>[];
  assert.equal(items[0].isDeleted, true);
  assert.equal(items[1].isDeleted, false);
  assert.deepEqual(
    (items[0].metadata as Record<string, unknown>).removedReason,
    "community_book_deleted"
  );
  // Legacy mirrors drop the retired title.
  assert.deepEqual(update.bookTitles, ["The BFG"]);
  assert.equal(update.schemaVersion, 2);
});

test("matches an item that only carries an isbn_ bookId", () => {
  const update = buildAllocationCascade(
    {
      assignmentItems: [
        { id: "a", title: "Matilda", bookId: `isbn_${ISBN}`, isDeleted: false },
      ],
    },
    { isbn: ISBN },
    STAMP
  );

  assert.ok(update);
  const items = update.assignmentItems as Record<string, unknown>[];
  assert.equal(items[0].isDeleted, true);
  assert.deepEqual(update.bookTitles, []);
  assert.deepEqual(update.bookIds, []);
});

test("matches case-insensitively via isbnNormalized", () => {
  const update = buildAllocationCascade(
    {
      assignmentItems: [
        { id: "a", title: "Book X", isbnNormalized: "123456789X", isDeleted: false },
      ],
    },
    { isbn: "123456789x" },
    STAMP
  );

  assert.ok(update);
  assert.equal(
    (update.assignmentItems as Record<string, unknown>[])[0].isDeleted,
    true
  );
});

test("materializes a legacy allocation and preserves positional item ids", () => {
  const update = buildAllocationCascade(
    {
      bookTitles: ["Matilda", "The BFG"],
      bookIds: [`isbn_${ISBN}`, "isbn_9780141365404"],
    },
    { isbn: ISBN },
    STAMP
  );

  assert.ok(update);
  const items = update.assignmentItems as Record<string, unknown>[];
  assert.equal(items.length, 2);
  // Ids must match AllocationModel._legacyItemId so per-student overrides
  // that reference them keep resolving.
  assert.equal(items[0].id, `legacy_0_isbn_${ISBN}`);
  assert.equal(items[1].id, "legacy_1_isbn_9780141365404");
  assert.equal(items[0].isDeleted, true);
  assert.equal(items[1].isDeleted, false);
  assert.deepEqual(update.bookTitles, ["The BFG"]);
  assert.deepEqual(update.bookIds, ["isbn_9780141365404"]);
});

test("retires the book from per-student override additions", () => {
  const update = buildAllocationCascade(
    {
      assignmentItems: [
        { id: "a", title: "Other", isbn: "9999999999999", isDeleted: false },
      ],
      studentOverrides: {
        stu1: {
          removedItemIds: [],
          addedItems: [
            { id: "o1", title: "Matilda", isbn: ISBN, isDeleted: false },
          ],
        },
        stu2: { removedItemIds: [], addedItems: [] },
      },
    },
    { isbn: ISBN },
    STAMP
  );

  assert.ok(update);
  const overrides = update.studentOverrides as Record<
    string,
    Record<string, unknown>
  >;
  const added = overrides.stu1.addedItems as Record<string, unknown>[];
  assert.equal(added[0].isDeleted, true);
  // Untouched students are carried through unchanged.
  assert.deepEqual(overrides.stu2.addedItems, []);
});

test("returns null when the allocation never referenced the book", () => {
  const update = buildAllocationCascade(
    {
      assignmentItems: [
        { id: "a", title: "The BFG", isbn: "9780141365404", isDeleted: false },
      ],
    },
    { isbn: ISBN },
    STAMP
  );

  assert.equal(update, null);
});

test("matches a school-local book by document id when it has no ISBN", () => {
  const update = buildAllocationCascade(
    {
      assignmentItems: [
        { id: "a", title: "Class Reader", bookId: "localBook42", isDeleted: false },
        { id: "b", title: "Other", bookId: "localBook7", isDeleted: false },
      ],
    },
    { bookId: "localBook42" },
    { ...STAMP, reason: "school_library_book_deleted" }
  );

  assert.ok(update);
  const items = update.assignmentItems as Record<string, unknown>[];
  assert.equal(items[0].isDeleted, true);
  assert.equal(items[1].isDeleted, false);
  assert.deepEqual(update.bookIds, ["localBook7"]);
  assert.equal(
    (items[0].metadata as Record<string, unknown>).removedReason,
    "school_library_book_deleted"
  );
});

test("bookId matching is exact, not a prefix or case-folded match", () => {
  const update = buildAllocationCascade(
    {
      assignmentItems: [
        { id: "a", title: "Nearly", bookId: "localBook420", isDeleted: false },
        { id: "b", title: "Case", bookId: "LOCALBOOK42", isDeleted: false },
      ],
    },
    { bookId: "localBook42" },
    STAMP
  );

  assert.equal(update, null);
});

test("returns null when neither isbn nor bookId is supplied", () => {
  const update = buildAllocationCascade(
    {
      assignmentItems: [
        { id: "a", title: "Matilda", isbn: ISBN, isDeleted: false },
      ],
    },
    {},
    STAMP
  );

  assert.equal(update, null);
});

test("returns null when the only match is already retired", () => {
  const update = buildAllocationCascade(
    {
      assignmentItems: [
        { id: "a", title: "Matilda", isbn: ISBN, isDeleted: true },
      ],
    },
    { isbn: ISBN },
    STAMP
  );

  assert.equal(update, null);
});
