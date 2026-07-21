import test from "node:test";
import assert from "node:assert/strict";
import * as serverOps from "../src/allocationCascade";
import * as schoolPortal from "../../../school-admin-web/src/lib/firestore/allocation-cascade";

// school-admin-web sits outside the pnpm workspace and cannot import
// @lumi/server-ops, so its allocation cascade is a manual mirror. Both portals
// delete books from the same collections; if the two implementations drifted,
// one would leave students holding assignments for a book that no longer
// exists — the exact failure the cascade was written to prevent, and one that
// only shows up in production data. This runs both over identical fixtures.

const STAMP = {
  removedAt: new Date("2026-07-21T00:00:00Z"),
  removedBy: "admin1",
  reason: "school_library_book_deleted",
};

const ISBN = "9780141354828";

const FIXTURES: {
  name: string;
  data: Record<string, unknown>;
  target: { isbn?: string | null; bookId?: string | null };
}[] = [
  {
    name: "structured item matched by isbn",
    data: {
      assignmentItems: [
        { id: "a", title: "Matilda", isbn: ISBN, isDeleted: false },
        { id: "b", title: "The BFG", isbn: "9780141365404", isDeleted: false },
      ],
      bookTitles: ["Matilda", "The BFG"],
      bookIds: [],
    },
    target: { isbn: ISBN },
  },
  {
    name: "matched via isbn_ bookId only",
    data: {
      assignmentItems: [
        { id: "a", title: "Matilda", bookId: `isbn_${ISBN}`, isDeleted: false },
      ],
    },
    target: { isbn: ISBN },
  },
  {
    name: "isbnNormalized wins over isbn",
    data: {
      assignmentItems: [
        {
          id: "a",
          title: "Book X",
          isbn: "different",
          isbnNormalized: "123456789X",
          isDeleted: false,
        },
      ],
    },
    target: { isbn: "123456789x" },
  },
  {
    name: "legacy positional arrays",
    data: {
      bookTitles: ["Matilda", "The BFG"],
      bookIds: [`isbn_${ISBN}`, "isbn_9780141365404"],
    },
    target: { isbn: ISBN },
  },
  {
    name: "legacy with trailing unpaired ids",
    data: {
      bookTitles: ["Only Title"],
      bookIds: ["", `isbn_${ISBN}`],
    },
    target: { isbn: ISBN },
  },
  {
    name: "per-student override additions",
    data: {
      assignmentItems: [
        { id: "a", title: "Other", isbn: "9999999999999", isDeleted: false },
      ],
      studentOverrides: {
        stu1: {
          removedItemIds: ["x"],
          addedItems: [
            { id: "o1", title: "Matilda", isbn: ISBN, isDeleted: false },
          ],
        },
        stu2: { removedItemIds: [], addedItems: [] },
        stu3: "malformed",
      },
    },
    target: { isbn: ISBN },
  },
  {
    name: "school-local bookId match",
    data: {
      assignmentItems: [
        { id: "a", title: "Reader", bookId: "localBook42", isDeleted: false },
        { id: "b", title: "Other", bookId: "localBook7", isDeleted: false },
      ],
    },
    target: { bookId: "localBook42" },
  },
  {
    name: "bookId near-miss (prefix and case)",
    data: {
      assignmentItems: [
        { id: "a", title: "Nearly", bookId: "localBook420", isDeleted: false },
        { id: "b", title: "Case", bookId: "LOCALBOOK42", isDeleted: false },
      ],
    },
    target: { bookId: "localBook42" },
  },
  {
    name: "already retired",
    data: {
      assignmentItems: [
        { id: "a", title: "Matilda", isbn: ISBN, isDeleted: true },
      ],
    },
    target: { isbn: ISBN },
  },
  {
    name: "no match",
    data: {
      assignmentItems: [
        { id: "a", title: "The BFG", isbn: "9780141365404", isDeleted: false },
      ],
    },
    target: { isbn: ISBN },
  },
  {
    name: "empty target",
    data: {
      assignmentItems: [
        { id: "a", title: "Matilda", isbn: ISBN, isDeleted: false },
      ],
    },
    target: {},
  },
  {
    name: "hostile shapes",
    data: {
      assignmentItems: ["nonsense", null, 42],
      bookTitles: "not-an-array",
      bookIds: null,
      studentOverrides: [],
    },
    target: { isbn: ISBN },
  },
];

test("both portals build identical allocation cascades", () => {
  for (const fixture of FIXTURES) {
    const a = serverOps.buildAllocationCascade(
      structuredClone(fixture.data),
      fixture.target,
      STAMP
    );
    const b = schoolPortal.buildAllocationCascade(
      structuredClone(fixture.data),
      fixture.target,
      STAMP
    );
    assert.deepEqual(b, a, `cascade diverged for fixture: ${fixture.name}`);
  }
});

test("both portals resolve item ISBNs identically", () => {
  const items: Record<string, unknown>[] = [
    { isbn: ISBN },
    { isbnNormalized: "123456789X", isbn: "ignored" },
    { bookId: `isbn_${ISBN}` },
    { bookId: "ISBN_ABC" },
    { bookId: "isbn_" },
    { bookId: "localBook42" },
    { isbn: "   " },
    { isbn: 42 },
    {},
  ];
  for (const item of items) {
    assert.equal(
      schoolPortal.itemIsbn(item),
      serverOps.itemIsbn(item),
      `itemIsbn diverged for ${JSON.stringify(item)}`
    );
  }
});

test("both portals materialize legacy items identically", () => {
  const cases: [unknown, unknown][] = [
    [["A", "B"], ["id1", "id2"]],
    [["A"], ["id1", "id2", "id3"]],
    [[], ["id1"]],
    [["", "  ", "C"], []],
    ["not-an-array", null],
    [null, undefined],
  ];
  for (const [titles, ids] of cases) {
    assert.deepEqual(
      schoolPortal.materializeLegacyItems(titles, ids),
      serverOps.materializeLegacyItems(titles, ids),
      `materializeLegacyItems diverged for ${JSON.stringify([titles, ids])}`
    );
  }
});
