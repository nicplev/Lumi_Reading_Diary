/**
 * Server-maintained view aggregates on the student doc (perf plan C7):
 *
 *  - `feelingsByDay`  — rolling ~90-day map of school-local day key
 *                        (YYYY-MM-DD) → {feeling: count}. Replaces the app's
 *                        400-log live query behind the feelings tracker.
 *  - `latestParentComment` — the newest log carrying parent-comment content
 *                        (chips or free text), denormalised so the teacher
 *                        student-detail screen reads one doc instead of
 *                        scanning 50 logs.
 *
 * Both are TOP-LEVEL student-doc fields (not nested under `stats`) so
 * firestore.rules can deny client writes via the same affectedKeys denylist
 * that protects `access`/`autoAward`. `latestParentComment` is
 * integrity-sensitive: it renders in the teacher UI attributed to a parent,
 * so a client must never be able to forge it.
 *
 * Maintained by the same readingLogs trigger as the stats
 * (stats_aggregation.ts), recomputed by the weekly reconciler, and seeded by
 * scripts/backfill_student_view_aggregates.js.
 */

import * as admin from "firebase-admin";
import {localDateString, resolveOccurrenceDate, shiftDays} from "./dateUtils";

/** Rolling window (school-local days) kept in `feelingsByDay` — matches the
 * app's former 366-day query floor so the card's "All" tab keeps its reach. */
export const FEELINGS_WINDOW_DAYS = 366;

/** How many newest logs the bounded latest-comment recompute scans — matches
 * the app's former live query. */
export const LATEST_COMMENT_SCAN_LIMIT = 50;

/** Cap on denormalised free text so a giant comment can't bloat the student
 * doc. The full text stays on the log; the card preview is 3 lines anyway. */
export const LATEST_COMMENT_TEXT_CAP = 500;

export interface LatestParentComment {
  logId: string;
  date: admin.firestore.Timestamp;
  feeling: string | null;
  presetChips: string[];
  freeText: string;
  parentId: string | null;
  parentName: string;
  // Denormalised comment-thread state so the teacher UI's unread ("New")
  // badge stays accurate without reading the log. Maintained because thread
  // mirror writes are aggregate-relevant (see viewAggregatesRelevantChange).
  lastCommentAt: admin.firestore.Timestamp | null;
  lastCommentByRole: string | null;
  commentsViewedAt: Record<string, admin.firestore.Timestamp>;
}

/**
 * Parent-comment content of a log, mirroring the app's extraction rules:
 * chips from `parentCommentSelections`; free text from
 * `parentCommentFreeText`, falling back to legacy `parentComment` ONLY when
 * no chips exist (otherwise it duplicates them).
 * @param {FirebaseFirestore.DocumentData | null | undefined} log Log data.
 * @return {{chips: string[], freeText: string} | null} Content, or null when
 *   the log carries no parent comment.
 */
export function extractParentCommentContent(
  log: FirebaseFirestore.DocumentData | null | undefined,
): {chips: string[]; freeText: string} | null {
  if (!log) return null;
  const rawChips = log.parentCommentSelections;
  const chips = Array.isArray(rawChips) ?
    rawChips.filter((c): c is string => typeof c === "string") :
    [];
  let freeText = String(log.parentCommentFreeText ?? "").trim();
  if (freeText.length === 0 && chips.length === 0) {
    freeText = String(log.parentComment ?? "").trim();
  }
  if (chips.length === 0 && freeText.length === 0) return null;
  return {chips, freeText: freeText.slice(0, LATEST_COMMENT_TEXT_CAP)};
}

/**
 * The oldest day key still inside the rolling feelings window.
 * @param {string} todayKey School-local YYYY-MM-DD for "today".
 * @return {string} Inclusive lower-bound day key.
 */
export function feelingsWindowFloor(todayKey: string): string {
  return shiftDays(todayKey, -(FEELINGS_WINDOW_DAYS - 1));
}

/**
 * Builds the full feelings map from log docs. Includes every log with a
 * non-empty `childFeeling` regardless of status — parity with the app's
 * feelings tracker, which never filtered by status.
 * @param {FirebaseFirestore.DocumentData[]} logs Log doc data.
 * @param {string} tz School timezone.
 * @param {string} todayKey School-local day key for "today".
 * @return {Record<string, Record<string, number>>} day → feeling → count.
 */
export function buildFeelingsByDay(
  logs: FirebaseFirestore.DocumentData[],
  tz: string,
  todayKey: string,
): Record<string, Record<string, number>> {
  const floor = feelingsWindowFloor(todayKey);
  const map: Record<string, Record<string, number>> = {};
  for (const log of logs) {
    const feeling = String(log.childFeeling ?? "").trim();
    if (!feeling) continue;
    const ts = log.date as admin.firestore.Timestamp | undefined;
    if (!ts) continue;
    const day = resolveOccurrenceDate(log.occurredOn, ts.toDate(), tz);
    if (day < floor) continue;
    const bucket = (map[day] ??= {});
    bucket[feeling] = (bucket[feeling] ?? 0) + 1;
  }
  return map;
}

/**
 * Drops window-expired day keys from a stored feelings map (in place on a
 * copy). Used by the incremental path so the map can't grow unboundedly.
 * @param {Record<string, Record<string, number>>} stored Stored map.
 * @param {string} todayKey School-local day key for "today".
 * @return {Record<string, Record<string, number>>} Pruned copy.
 */
export function pruneFeelingsWindow(
  stored: Record<string, Record<string, number>>,
  todayKey: string,
): Record<string, Record<string, number>> {
  const floor = feelingsWindowFloor(todayKey);
  const out: Record<string, Record<string, number>> = {};
  for (const [day, bucket] of Object.entries(stored)) {
    if (day >= floor) out[day] = bucket;
  }
  return out;
}

/**
 * Applies one log transition (create/update/delete) to a stored feelings map.
 * @param {Record<string, Record<string, number>>} stored Stored map (not
 *   mutated).
 * @param {FirebaseFirestore.DocumentData | null} before Pre-write log data.
 * @param {FirebaseFirestore.DocumentData | null} after Post-write log data.
 * @param {string} tz School timezone.
 * @param {string} todayKey School-local day key for "today".
 * @return {Record<string, Record<string, number>>} Updated, pruned copy.
 */
export function applyFeelingsDelta(
  stored: Record<string, Record<string, number>>,
  before: FirebaseFirestore.DocumentData | null,
  after: FirebaseFirestore.DocumentData | null,
  tz: string,
  todayKey: string,
): Record<string, Record<string, number>> {
  const map: Record<string, Record<string, number>> = {};
  for (const [day, bucket] of Object.entries(stored)) {
    map[day] = {...bucket};
  }

  const adjust = (
    log: FirebaseFirestore.DocumentData | null,
    delta: number,
  ) => {
    if (!log) return;
    const feeling = String(log.childFeeling ?? "").trim();
    if (!feeling) return;
    const ts = log.date as admin.firestore.Timestamp | undefined;
    if (!ts) return;
    const day = resolveOccurrenceDate(log.occurredOn, ts.toDate(), tz);
    const bucket = (map[day] ??= {});
    const next = (bucket[feeling] ?? 0) + delta;
    if (next > 0) {
      bucket[feeling] = next;
    } else {
      delete bucket[feeling];
      if (Object.keys(bucket).length === 0) delete map[day];
    }
  };

  adjust(before, -1);
  adjust(after, +1);
  return pruneFeelingsWindow(map, todayKey);
}

/**
 * Resolves a parent's display name the same way the app did: school parents
 * doc first, then the school users mirror, else a neutral fallback.
 * @param {FirebaseFirestore.Firestore} db Firestore handle.
 * @param {string} schoolId School id.
 * @param {string | null} parentId Parent id from the log.
 * @return {Promise<string>} Display name.
 */
export async function resolveParentName(
  db: FirebaseFirestore.Firestore,
  schoolId: string,
  parentId: string | null,
): Promise<string> {
  if (!parentId) return "Parent";
  const schoolRef = db.collection("schools").doc(schoolId);
  for (const coll of ["parents", "users"]) {
    const snap = await schoolRef.collection(coll).doc(parentId).get();
    const name = String(snap.data()?.fullName ?? "").trim();
    if (name) return name;
  }
  return "Parent";
}

/**
 * Builds the denormalised latest-comment payload from a log doc, or null.
 * @param {string} logId Log doc id.
 * @param {FirebaseFirestore.DocumentData} log Log data.
 * @param {string} parentName Resolved parent display name.
 * @return {LatestParentComment | null} Payload, or null without content.
 */
export function buildLatestParentComment(
  logId: string,
  log: FirebaseFirestore.DocumentData,
  parentName: string,
): LatestParentComment | null {
  const content = extractParentCommentContent(log);
  const date = log.date as admin.firestore.Timestamp | undefined;
  if (!content || !date) return null;
  const viewedRaw = log.commentsViewedAt;
  const commentsViewedAt: Record<string, admin.firestore.Timestamp> = {};
  if (viewedRaw && typeof viewedRaw === "object") {
    for (const [uid, ts] of Object.entries(viewedRaw)) {
      if (ts instanceof admin.firestore.Timestamp) commentsViewedAt[uid] = ts;
    }
  }
  return {
    logId,
    date,
    feeling: String(log.childFeeling ?? "").trim() || null,
    presetChips: content.chips,
    freeText: content.freeText,
    parentId: typeof log.parentId === "string" ? log.parentId : null,
    parentName,
    lastCommentAt:
      log.lastCommentAt instanceof admin.firestore.Timestamp ?
        log.lastCommentAt :
        null,
    lastCommentByRole:
      typeof log.lastCommentByRole === "string" ? log.lastCommentByRole : null,
    commentsViewedAt,
  };
}

/**
 * Bounded full recompute of both aggregates for one student. Used by the
 * weekly reconciler (via reconcileStudentStats), the trigger's self-heal
 * path, the latest-comment invalidation path, and the backfill script.
 *
 * Query shapes deliberately mirror the app's former live queries (90-day
 * window; newest-50 comment scan) except that neither filters by classId —
 * the aggregate describes the student, not one class enrolment, so it stays
 * correct across class moves.
 * @param {FirebaseFirestore.Firestore} db Firestore handle.
 * @param {string} schoolId School id.
 * @param {string} studentId Student id.
 * @param {string} tz School timezone.
 * @return {Promise<object>} Both aggregates ({feelingsByDay,
 *   latestParentComment}).
 */
export async function recomputeStudentViewAggregates(
  db: FirebaseFirestore.Firestore,
  schoolId: string,
  studentId: string,
  tz: string,
): Promise<{
  feelingsByDay: Record<string, Record<string, number>>;
  latestParentComment: LatestParentComment | null;
}> {
  const logsColl = db.collection(`schools/${schoolId}/readingLogs`);
  const todayKey = localDateString(new Date(), tz);

  const windowStart = new Date(
    Date.now() - FEELINGS_WINDOW_DAYS * 24 * 60 * 60 * 1000,
  );
  const feelingsSnap = await logsColl
    .where("studentId", "==", studentId)
    .where("date", ">=", admin.firestore.Timestamp.fromDate(windowStart))
    .get();
  const feelingsByDay = buildFeelingsByDay(
    feelingsSnap.docs.map((d) => d.data()),
    tz,
    todayKey,
  );

  const commentSnap = await logsColl
    .where("studentId", "==", studentId)
    .orderBy("date", "desc")
    .limit(LATEST_COMMENT_SCAN_LIMIT)
    .get();
  let latestParentComment: LatestParentComment | null = null;
  for (const doc of commentSnap.docs) {
    const data = doc.data();
    if (!extractParentCommentContent(data)) continue;
    const parentName = await resolveParentName(
      db,
      schoolId,
      typeof data.parentId === "string" ? data.parentId : null,
    );
    latestParentComment = buildLatestParentComment(doc.id, data, parentName);
    break;
  }

  return {feelingsByDay, latestParentComment};
}

/**
 * True when a log write can change either view aggregate — the trigger's
 * no-op guard must NOT skip these even when no stat field moved.
 * @param {FirebaseFirestore.DocumentData | null} before Pre-write log data.
 * @param {FirebaseFirestore.DocumentData | null} after Post-write log data.
 * @return {boolean} True when aggregates may change.
 */
export function viewAggregatesRelevantChange(
  before: FirebaseFirestore.DocumentData | null,
  after: FirebaseFirestore.DocumentData | null,
): boolean {
  if (!before || !after) return true; // create / delete
  const feelingChanged =
    String(before.childFeeling ?? "") !== String(after.childFeeling ?? "");
  const beforeContent = extractParentCommentContent(before);
  const afterContent = extractParentCommentContent(after);
  const commentChanged =
    JSON.stringify(beforeContent) !== JSON.stringify(afterContent);
  const beforeDate = before.date as admin.firestore.Timestamp | undefined;
  const afterDate = after.date as admin.firestore.Timestamp | undefined;
  const dateChanged =
    (beforeDate?.toMillis() ?? null) !== (afterDate?.toMillis() ?? null);
  // Thread-state mirror writes (lastCommentAt / commentsViewedAt) feed the
  // unread badge in the denormalised latest comment. Validation stamps touch
  // none of these, so the trigger's hottest wasted firing stays skipped.
  const threadStateChanged =
    threadStateKey(before) !== threadStateKey(after);
  return feelingChanged || commentChanged || dateChanged || threadStateChanged;
}

/**
 * Canonical string for a log's comment-thread mirror state.
 * @param {FirebaseFirestore.DocumentData} log Log data.
 * @return {string} Comparable key.
 */
function threadStateKey(log: FirebaseFirestore.DocumentData): string {
  const at = log.lastCommentAt instanceof admin.firestore.Timestamp ?
    log.lastCommentAt.toMillis() :
    null;
  const viewedRaw = log.commentsViewedAt;
  const viewed: Record<string, number> = {};
  if (viewedRaw && typeof viewedRaw === "object") {
    for (const [uid, ts] of Object.entries(viewedRaw)) {
      if (ts instanceof admin.firestore.Timestamp) viewed[uid] = ts.toMillis();
    }
  }
  return JSON.stringify([
    at,
    String(log.lastCommentByRole ?? ""),
    Object.entries(viewed).sort(),
  ]);
}
