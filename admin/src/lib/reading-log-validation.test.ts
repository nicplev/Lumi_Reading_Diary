import assert from "node:assert/strict";
import test from "node:test";
import { validateReadingLogForReview } from "./reading-log-validation.ts";

test("accepts a linked guardian log with reasonable minutes", () => {
  assert.deepEqual(
    validateReadingLogForReview(
      { minutesRead: 20, parentId: "parent-1" },
      { exists: true, parentIds: ["parent-1"] }
    ),
    []
  );
});

test("rejects malformed or unreasonable minutes", () => {
  for (const minutesRead of [0, 241, "not-a-number", undefined]) {
    assert.ok(
      validateReadingLogForReview(
        { minutesRead, parentId: "parent-1" },
        { exists: true, parentIds: ["parent-1"] }
      ).includes("Minutes read must be between 1 and 240")
    );
  }
});

test("rejects a missing student without adding a misleading link error", () => {
  assert.deepEqual(
    validateReadingLogForReview(
      { minutesRead: 20, parentId: "parent-1" },
      { exists: false, parentIds: [] }
    ),
    ["Student does not exist"]
  );
});

test("requires guardian linkage but permits teacher-proxy logs", () => {
  assert.deepEqual(
    validateReadingLogForReview(
      { minutesRead: 20, parentId: "parent-2" },
      { exists: true, parentIds: ["parent-1"] }
    ),
    ["Parent not linked to this student"]
  );
  assert.deepEqual(
    validateReadingLogForReview(
      { minutesRead: 20, parentId: "teacher-1", loggedByRole: "teacher" },
      { exists: true, parentIds: [] }
    ),
    []
  );
});
