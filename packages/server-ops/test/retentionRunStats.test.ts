import test from "node:test";
import assert from "node:assert/strict";
import { readComprehensionRetentionRunStats } from "../src/setComprehensionRetentionConfig";

test("reads canonical cron and manual retention statistics", () => {
  const stats = readComprehensionRetentionRunStats({
    deletedCount: 4,
    failedCount: 1,
    durationMs: 250,
    schoolCount: 3,
    legacyDefaultRetentionDays: 90,
    retentionPolicyCounts: { 7: 1, 30: 1, 90: 1 },
    fallbackSchoolCount: 1,
    legacySevenDaySchoolCount: 1,
    trigger: "manual",
  });

  assert.deepEqual(stats, {
    deletedCount: 4,
    failedCount: 1,
    durationMs: 250,
    schoolCount: 3,
    legacyDefaultRetentionDays: 90,
    retentionPolicyCounts: { 7: 1, 30: 1, 90: 1 },
    fallbackSchoolCount: 1,
    legacySevenDaySchoolCount: 1,
    trigger: "manual",
    cutoffISO: undefined,
    retentionDays: undefined,
  });
});

test("continues to read legacy cutoff-based run statistics", () => {
  assert.deepEqual(
    readComprehensionRetentionRunStats({
      deletedCount: 2,
      failedCount: 0,
      durationMs: 15,
      cutoffISO: "2026-06-01T00:00:00.000Z",
      retentionDays: 30,
    }),
    {
      deletedCount: 2,
      failedCount: 0,
      durationMs: 15,
      schoolCount: undefined,
      legacyDefaultRetentionDays: undefined,
      retentionPolicyCounts: undefined,
      fallbackSchoolCount: undefined,
      legacySevenDaySchoolCount: undefined,
      trigger: undefined,
      cutoffISO: "2026-06-01T00:00:00.000Z",
      retentionDays: 30,
    }
  );
});

test("rejects malformed required run statistics", () => {
  assert.equal(readComprehensionRetentionRunStats({
    deletedCount: Number.NaN,
    failedCount: 0,
    durationMs: 15,
  }), null);
});
