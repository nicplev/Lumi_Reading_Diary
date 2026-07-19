#!/usr/bin/env node
"use strict";

// One-time seed for the server-maintained student view aggregates
// (`feelingsByDay` + `latestParentComment`, perf plan C7). Dry-run is the
// default; pass --apply to write. Optionally scope with --school <id>.
//
// The computation intentionally mirrors
// functions/src/student_view_aggregates.ts (recomputeStudentViewAggregates):
// after this one-shot seed, the readingLogs trigger maintains the fields and
// the weekly Sunday reconcile self-heals any drift, so this copy never needs
// to stay in lockstep long-term.
//
// Prints aggregate counts only; never prints student names or comment text.

const admin = require("../functions/node_modules/firebase-admin");

const PROJECT_ID = "lumi-ninc-au";
const APPLY = process.argv.includes("--apply");
const schoolArgIx = process.argv.indexOf("--school");
const ONLY_SCHOOL = schoolArgIx >= 0 ? process.argv[schoolArgIx + 1] : null;

const FEELINGS_WINDOW_DAYS = 366;
const LATEST_COMMENT_SCAN_LIMIT = 50;
const LATEST_COMMENT_TEXT_CAP = 500;
const DEFAULT_TIMEZONE = "Australia/Sydney";

function localDateString(d, tz) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: tz,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(d);
}

function shiftDays(dateStr, delta) {
  const [y, m, d] = dateStr.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d + delta));
  return dt.toISOString().slice(0, 10);
}

function extractParentCommentContent(log) {
  if (!log) return null;
  const rawChips = log.parentCommentSelections;
  const chips = Array.isArray(rawChips)
    ? rawChips.filter((c) => typeof c === "string")
    : [];
  let freeText = String(log.parentCommentFreeText ?? "").trim();
  if (freeText.length === 0 && chips.length === 0) {
    freeText = String(log.parentComment ?? "").trim();
  }
  if (chips.length === 0 && freeText.length === 0) return null;
  return { chips, freeText: freeText.slice(0, LATEST_COMMENT_TEXT_CAP) };
}

async function resolveParentName(db, schoolId, parentId) {
  if (!parentId) return "Parent";
  const schoolRef = db.collection("schools").doc(schoolId);
  for (const coll of ["parents", "users"]) {
    const snap = await schoolRef.collection(coll).doc(parentId).get();
    const name = String((snap.data() || {}).fullName ?? "").trim();
    if (name) return name;
  }
  return "Parent";
}

async function computeForStudent(db, schoolId, studentId, tz) {
  const logsColl = db.collection(`schools/${schoolId}/readingLogs`);
  const todayKey = localDateString(new Date(), tz);
  const floor = shiftDays(todayKey, -(FEELINGS_WINDOW_DAYS - 1));

  const windowStart = new Date(
    Date.now() - FEELINGS_WINDOW_DAYS * 24 * 60 * 60 * 1000,
  );
  const feelingsSnap = await logsColl
    .where("studentId", "==", studentId)
    .where("date", ">=", admin.firestore.Timestamp.fromDate(windowStart))
    .get();

  const feelingsByDay = {};
  for (const doc of feelingsSnap.docs) {
    const data = doc.data();
    const feeling = String(data.childFeeling ?? "").trim();
    if (!feeling || !data.date) continue;
    const day = localDateString(data.date.toDate(), tz);
    if (day < floor) continue;
    feelingsByDay[day] = feelingsByDay[day] || {};
    feelingsByDay[day][feeling] = (feelingsByDay[day][feeling] || 0) + 1;
  }

  const commentSnap = await logsColl
    .where("studentId", "==", studentId)
    .orderBy("date", "desc")
    .limit(LATEST_COMMENT_SCAN_LIMIT)
    .get();
  let latestParentComment = null;
  for (const doc of commentSnap.docs) {
    const data = doc.data();
    const content = extractParentCommentContent(data);
    if (!content || !data.date) continue;
    const parentId = typeof data.parentId === "string" ? data.parentId : null;
    latestParentComment = {
      logId: doc.id,
      date: data.date,
      feeling: String(data.childFeeling ?? "").trim() || null,
      presetChips: content.chips,
      freeText: content.freeText,
      parentId,
      parentName: await resolveParentName(db, schoolId, parentId),
      lastCommentAt: data.lastCommentAt || null,
      lastCommentByRole:
        typeof data.lastCommentByRole === "string"
          ? data.lastCommentByRole
          : null,
      commentsViewedAt:
        data.commentsViewedAt && typeof data.commentsViewedAt === "object"
          ? data.commentsViewedAt
          : {},
    };
    break;
  }

  return { feelingsByDay, latestParentComment };
}

async function main() {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
  });
  const db = admin.firestore();

  const schoolsSnap = ONLY_SCHOOL
    ? { docs: [await db.collection("schools").doc(ONLY_SCHOOL).get()] }
    : await db.collection("schools").get();

  let students = 0;
  let withFeelings = 0;
  let withComment = 0;
  let written = 0;

  for (const schoolDoc of schoolsSnap.docs) {
    if (!schoolDoc.exists) {
      console.error(`school not found: ${ONLY_SCHOOL}`);
      process.exitCode = 1;
      return;
    }
    const schoolId = schoolDoc.id;
    const tz = String((schoolDoc.data() || {}).timezone ?? DEFAULT_TIMEZONE);
    const studentsSnap = await db
      .collection(`schools/${schoolId}/students`)
      .get();

    for (const studentDoc of studentsSnap.docs) {
      students += 1;
      const { feelingsByDay, latestParentComment } = await computeForStudent(
        db,
        schoolId,
        studentDoc.id,
        tz,
      );
      if (Object.keys(feelingsByDay).length > 0) withFeelings += 1;
      if (latestParentComment) withComment += 1;
      if (APPLY) {
        await studentDoc.ref.update({ feelingsByDay, latestParentComment });
        written += 1;
      }
    }
    console.log(`school ${schoolId}: ${studentsSnap.size} students processed`);
  }

  console.log(
    `${APPLY ? "APPLIED" : "DRY RUN"}: students=${students} ` +
      `withFeelings=${withFeelings} withComment=${withComment} ` +
      `written=${written}`,
  );
}

main().catch((err) => {
  console.error(err.message || err);
  process.exitCode = 1;
});
