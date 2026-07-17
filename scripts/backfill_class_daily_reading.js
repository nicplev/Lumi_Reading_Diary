#!/usr/bin/env node
"use strict";

// One-time backfill/reconciliation for the server-owned class/day summaries.
// Dry-run is the default. Pass --apply only after the summary trigger, Rules
// and index have deployed. Output is aggregate-only; no school/student IDs or
// reading content are printed.

const admin = require("../functions/node_modules/firebase-admin");

const PROJECT_ID = "lumi-ninc-au";
const APPLY = process.argv.includes("--apply");

async function collectionGroupCount(db, name) {
  return (await db.collectionGroup(name).count().get()).data().count;
}

async function verifySummaries(db) {
  const [states, summaries] = await Promise.all([
    db.collectionGroup("readingLogSummaryState").get(),
    db.collectionGroup("classDailyReading").get(),
  ]);
  const stateMinutes = states.docs.reduce(
    (total, doc) => total + (Number(doc.data().minutes) || 0),
    0,
  );
  let summaryLogs = 0;
  let summaryMinutes = 0;
  let inconsistentShards = 0;
  for (const doc of summaries.docs) {
    const data = doc.data();
    const students = data.students && typeof data.students === "object" ?
      Object.values(data.students) : [];
    const studentLogs = students.reduce(
      (total, metric) => total + (Number(metric.logs) || 0),
      0,
    );
    const studentMinutes = students.reduce(
      (total, metric) => total + (Number(metric.minutes) || 0),
      0,
    );
    summaryLogs += Number(data.logCount) || 0;
    summaryMinutes += Number(data.totalMinutes) || 0;
    if (
      studentLogs !== data.logCount ||
      studentMinutes !== data.totalMinutes ||
      students.length !== data.activeStudentCount
    ) {
      inconsistentShards += 1;
    }
  }
  return {
    projectionStates: states.size,
    stateMinutes,
    summaryLogCount: summaryLogs,
    summaryMinutes,
    inconsistentShards,
    exact:
      states.size === summaryLogs &&
      stateMinutes === summaryMinutes &&
      inconsistentShards === 0,
  };
}

async function main() {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
  });
  const db = admin.firestore();
  const [schools, logs, states, summaries] = await Promise.all([
    db.collection("schools").count().get(),
    collectionGroupCount(db, "readingLogs"),
    collectionGroupCount(db, "readingLogSummaryState"),
    collectionGroupCount(db, "classDailyReading"),
  ]);
  console.log(JSON.stringify({
    mode: APPLY ? "apply" : "dry-run",
    schools: schools.data().count,
    readingLogs: logs,
    existingProjectionStates: states,
    existingSummaryShards: summaries,
  }, null, 2));

  if (states > 0 || summaries > 0) {
    console.log(JSON.stringify({verification: await verifySummaries(db)}, null, 2));
  }

  if (!APPLY) return;
  const {reconcileClassDailyReadingPass} =
    require("../functions/lib/class_daily_reading.js");
  const result = await reconcileClassDailyReadingPass();
  const [finalStates, finalSummaries] = await Promise.all([
    collectionGroupCount(db, "readingLogSummaryState"),
    collectionGroupCount(db, "classDailyReading"),
  ]);
  console.log(JSON.stringify({
    applied: true,
    schoolsProcessed: result.schools,
    logsProcessed: result.logs,
    countedProjectionStates: finalStates,
    summaryShards: finalSummaries,
  }, null, 2));
  const verification = await verifySummaries(db);
  console.log(JSON.stringify({verification}, null, 2));
  if (!verification.exact) {
    throw new Error("Summary verification did not reconcile exactly");
  }
}

main()
  .catch((error) => {
    console.error(error instanceof Error ? error.message : "Backfill failed");
    process.exitCode = 1;
  })
  .finally(async () => {
    if (admin.apps.length > 0) await admin.app().delete();
  });
