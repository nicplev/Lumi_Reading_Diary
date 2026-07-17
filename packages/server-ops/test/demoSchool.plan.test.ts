import test from "node:test";
import assert from "node:assert/strict";
import { buildDemoSchoolPlan } from "../src/demoSchool/plan";

test("demo plan is deterministic and internally coherent", () => {
  const now = new Date("2026-07-17T09:00:00+10:00");
  const first = buildDemoSchoolPlan(now);
  const second = buildDemoSchoolPlan(now);
  assert.deepEqual(first, second);
  assert.equal(first.school.data.isDemo, true);
  assert.equal(first.students.length, 16);
  assert.equal(first.logs.length, 459);
  assert.equal(first.books.length, 3);
  assert.ok(first.students.every((student) => student.data.access?.status === "active"));
  assert.ok(first.students.every((student) => student.data.access?.academicYear === 2026));
});
test("demo plan contains no fake by-level card or global catalogue write", () => {
  const plan = buildDemoSchoolPlan(new Date("2026-07-17T09:00:00+10:00"));
  assert.deepEqual(
    plan.allocations.map((item) => item.id),
    ["demo_alloc_3g_bytitle", "demo_alloc_3g_freechoice"]
  );
  const byTitle = plan.allocations[0];
  assert.equal(byTitle.data.type, "byTitle");
  assert.equal(byTitle.data.assignmentItems.length, 3);
  assert.ok(
    byTitle.data.assignmentItems.every(
      (item: Record<string, unknown>) =>
        typeof item.isbnNormalized === "string" &&
        item.bookId === `isbn_${item.isbnNormalized}`
    )
  );
  assert.equal(plan.school.data.settings.comprehensionRecording.enabled, false);
});
