/**
 * Incremental student + class stats aggregation.
 *
 * The legacy `aggregateStudentStats` / `updateClassStats` triggers in
 * index.ts recompute stats from scratch by re-reading every counted log for
 * the student or class on every write. That's O(N) reads per write — fine
 * at Pilot scale, catastrophic at Large (10–100M reads/day from these two
 * triggers alone, plus the 540s function timeout risk).
 *
 * The two `apply*Delta` functions in this file replace that with O(1) reads:
 *  - read the aggregate doc (student or class) once
 *  - apply the per-log delta in memory using the before/after snapshots
 *  - re-derive streaks/rolling counts from a maintained `readingDates` array
 *  - write the updated stats once
 *
 * Two safety nets keep this from drifting:
 *  1. Self-heal — if `readingDates` is missing on the student doc, the
 *     delta path falls back to `reconcileStudentStats` (full recompute)
 *     and seeds the array. Same for `activeStudentIds` on classes.
 *  2. Weekly reconciler — `reconcileStatsScheduled` in index.ts iterates
 *     all students + classes and runs the full recompute path to repair
 *     any drift caused by missed triggers, mid-transaction crashes, etc.
 */

import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {
  MAX_REST_DAYS,
  buildIsCountingDay,
  computeGentleStreak,
  computeLongestStreak,
  countInWindow,
  localDateString,
  parseTermDates,
} from "./dateUtils";
import {DEFAULT_TIMEZONE} from "./access";

const COUNTED_STATUSES = ["completed", "partial"];

/**
 * Whether validateReadingLog has flagged this log invalid (e.g. minutesRead
 * outside 1–240, unlinked parent). Invalid logs are excluded from every stat
 * and award — before this check they were flagged AND still counted, so a
 * 600-minute log inflated totals and could win Top Reader.
 * @param {FirebaseFirestore.DocumentData | null | undefined} logData Log data.
 * @return {boolean} True when the log must not be counted.
 */
export function isInvalidatedLog(
  logData: FirebaseFirestore.DocumentData | null | undefined,
): boolean {
  return String(logData?.validationStatus ?? "") === "invalid";
}

const incrementalAggregationDoc = () =>
  admin.firestore().doc("platformConfig/incrementalAggregation");

export interface IncrementalAggregationConfig {
  studentStats: boolean;
  classStats: boolean;
}

// Config cache: the two stats triggers call readIncrementalConfig on EVERY
// reading-log write, so without a cache the config doc alone bills 2+ reads
// per log (~30k+/day at 15k logs). 60s TTL means a flag flip (including the
// no-deploy rollback: set both flags false) takes effect within a minute per
// warm instance — acceptable for a rollout/rollback lever.
const CONFIG_CACHE_TTL_MS = 60_000;
let cachedConfig: IncrementalAggregationConfig | null = null;
let cachedConfigAt = 0;

/**
 * Reads /platformConfig/incrementalAggregation (cached ~60s per instance).
 * Defaults BOTH flags to false so deploying this file alone is a no-op —
 * flip the flags from the super-admin portal (or directly in Firestore) to
 * roll incremental mode out per-feature.
 */
export async function readIncrementalConfig():
  Promise<IncrementalAggregationConfig> {
  const now = Date.now();
  if (cachedConfig && now - cachedConfigAt < CONFIG_CACHE_TTL_MS) {
    return cachedConfig;
  }
  const snap = await incrementalAggregationDoc().get();
  const data = snap.data() ?? {};
  cachedConfig = {
    studentStats: data.studentStats === true,
    classStats: data.classStats === true,
  };
  cachedConfigAt = now;
  return cachedConfig;
}

interface CountedLogFields {
  minutes: number;
  books: number;
  localDate: string;
  date: admin.firestore.Timestamp;
}

/**
 * Returns the contribution this log makes to aggregate stats, or null if
 * the log is not counted (draft, missing date, missing studentId, etc.).
 * Mirrors the `.where("status", "in", COUNTED_STATUSES)` filter the legacy
 * code applies during full re-aggregation.
 * @param {FirebaseFirestore.DocumentData | null} logData Snapshot data.
 * @param {string} tz Owning school's IANA timezone.
 * @return {CountedLogFields | null} Contribution, or null if uncounted.
 */
function extractCountedFields(
  logData: FirebaseFirestore.DocumentData | null,
  tz: string,
): CountedLogFields | null {
  if (!logData) return null;
  const status = String(logData.status ?? "");
  if (!COUNTED_STATUSES.includes(status)) return null;
  if (isInvalidatedLog(logData)) return null;
  const date = logData.date as admin.firestore.Timestamp | undefined;
  if (!date) return null;
  const localDate = localDateString(date.toDate(), tz);
  const minutes = Number(logData.minutesRead) || 0;
  const books = Array.isArray(logData.bookTitles) ? logData.bookTitles.length : 0;
  return {minutes, books, localDate, date};
}

/**
 * True when a reading-log UPDATE cannot change any aggregate stat, so both
 * stats triggers can skip it entirely (no config read, no doc reads, no
 * write). Creates and deletes always return false.
 *
 * A log's entire contribution to student AND class stats is derived from:
 * counted-ness (status ∈ COUNTED_STATUSES and not invalidated), studentId,
 * date, minutesRead, and bookTitles.length — see [extractCountedFields].
 * If none of those changed between the snapshots, recomputing is a no-op.
 *
 * This kills the two hottest wasted firings on the log write path:
 *  - validateReadingLog's post-create stamp (validation metadata only)
 *  - onCommentCreated's teacher-comment mirror write
 * while deliberately NOT skipping the updates that must recompute:
 *  - valid → invalid flips (counted-ness changes)
 *  - minute / date / status / studentId edits
 *  - deletes (widget-undo) and creates
 * @param {functions.Change<admin.firestore.DocumentSnapshot>} change
 *   Before/after snapshots from the onDocumentWritten event.
 * @return {boolean} True when the write is stats-irrelevant.
 */
export function isStatsNoopUpdate(
  change: functions.Change<admin.firestore.DocumentSnapshot>,
): boolean {
  if (!change.before.exists || !change.after.exists) return false;
  const b = change.before.data() ?? {};
  const a = change.after.data() ?? {};

  const bCounted =
    COUNTED_STATUSES.includes(String(b.status ?? "")) && !isInvalidatedLog(b);
  const aCounted =
    COUNTED_STATUSES.includes(String(a.status ?? "")) && !isInvalidatedLog(a);
  if (bCounted !== aCounted) return false;
  // Neither snapshot contributes to any stat → nothing can change.
  if (!bCounted) return true;

  const bDate = b.date as admin.firestore.Timestamp | undefined;
  const aDate = a.date as admin.firestore.Timestamp | undefined;
  return (
    String(b.studentId ?? "") === String(a.studentId ?? "") &&
    (bDate?.toMillis() ?? null) === (aDate?.toMillis() ?? null) &&
    (Number(b.minutesRead) || 0) === (Number(a.minutesRead) || 0) &&
    (Array.isArray(b.bookTitles) ? b.bookTitles.length : 0) ===
      (Array.isArray(a.bookTitles) ? a.bookTitles.length : 0)
  );
}

// ──────────────────────────────────────────────────────────────────────
// Student stats
// ──────────────────────────────────────────────────────────────────────

/**
 * Full recompute by re-reading every counted log for the student.
 * Used by:
 *  - the weekly reconciler
 *  - the delta path as a self-heal fallback when `readingDates` is missing
 *  - the backfill script
 *
 * Equivalent in semantics to the legacy `aggregateStudentStats` body. Kept
 * here so it can be invoked from anywhere and so the legacy trigger can be
 * cleanly retired once the flag has been fully on for a release.
 * @param {string} schoolId The school document ID.
 * @param {string} studentId The student document ID within the school.
 * @return {Promise<void>} Resolves when the student doc is updated.
 */
export async function reconcileStudentStats(
  schoolId: string,
  studentId: string,
): Promise<void> {
  const db = admin.firestore();
  const studentRef = db.doc(`schools/${schoolId}/students/${studentId}`);

  const logsSnap = await db
    .collection(`schools/${schoolId}/readingLogs`)
    .where("studentId", "==", studentId)
    .where("status", "in", COUNTED_STATUSES)
    .get();

  const schoolSnap = await db.collection("schools").doc(schoolId).get();
  const schoolData = schoolSnap.data() ?? {};
  const tz = String(schoolData.timezone ?? DEFAULT_TIMEZONE);
  const isCountingDay = buildIsCountingDay(parseTermDates(schoolData.termDates));

  const priorLongest =
    (await studentRef.get()).data()?.stats?.longestStreak ?? 0;

  let totalMinutesRead = 0;
  let totalBooksRead = 0;
  let lastReadingDate: admin.firestore.Timestamp | null = null;
  const readingDatesSet = new Set<string>();

  logsSnap.docs.forEach((doc) => {
    const data = doc.data();
    if (isInvalidatedLog(data)) return;
    totalMinutesRead += Number(data.minutesRead) || 0;
    totalBooksRead += Array.isArray(data.bookTitles) ? data.bookTitles.length : 0;
    const ts = data.date as admin.firestore.Timestamp | undefined;
    if (ts) {
      readingDatesSet.add(localDateString(ts.toDate(), tz));
      if (!lastReadingDate || ts.toMillis() > lastReadingDate.toMillis()) {
        lastReadingDate = ts;
      }
    }
  });

  const today = localDateString(new Date(), tz);
  const {currentStreak, restDaysRemaining} = computeGentleStreak(
    readingDatesSet, today, MAX_REST_DAYS, isCountingDay,
  );
  const longestStreak = Math.max(
    priorLongest,
    computeLongestStreak(readingDatesSet),
    currentStreak,
  );

  const totalReadingDays = readingDatesSet.size;
  const averageMinutesPerDay =
    totalReadingDays > 0 ? totalMinutesRead / totalReadingDays : 0;

  await studentRef.update({
    "stats.totalMinutesRead": totalMinutesRead,
    "stats.totalBooksRead": totalBooksRead,
    "stats.currentStreak": currentStreak,
    "stats.longestStreak": longestStreak,
    "stats.lastReadingDate": lastReadingDate,
    "stats.averageMinutesPerDay": Math.round(averageMinutesPerDay * 10) / 10,
    "stats.totalReadingDays": totalReadingDays,
    "stats.last30DaysCount": countInWindow(readingDatesSet, today, 30),
    "stats.last50DaysCount": countInWindow(readingDatesSet, today, 50),
    "stats.restDaysRemaining": restDaysRemaining,
    "stats.readingDates": [...readingDatesSet].sort(),
    "stats.lastUpdated": admin.firestore.FieldValue.serverTimestamp(),
  });
}

/**
 * Incremental student stats. Reads the student doc + school doc (for tz)
 * + at most one count query (when removing a date that may be shared with
 * another log), then writes back the updated stats. ~3 reads + 1 write
 * worst case, vs ~N reads for the full recompute.
 *
 * Falls back to `reconcileStudentStats` if `readingDates` is missing,
 * which keeps the trigger correct even before the backfill has run.
 * @param {functions.Change<admin.firestore.DocumentSnapshot>} change Trigger change snapshot.
 * @param {string} schoolId The school document ID from the trigger params.
 * @return {Promise<void>} Resolves when the student doc is updated.
 */
export async function applyStudentStatsDelta(
  change: functions.Change<admin.firestore.DocumentSnapshot>,
  schoolId: string,
): Promise<void> {
  const before = change.before.exists ? (change.before.data() ?? null) : null;
  const after = change.after.exists ? (change.after.data() ?? null) : null;
  const log = after ?? before;
  if (!log) return;

  const studentId = log.studentId;
  if (!studentId || typeof studentId !== "string") return;

  const db = admin.firestore();
  const studentRef = db.doc(`schools/${schoolId}/students/${studentId}`);

  const schoolSnap = await db.collection("schools").doc(schoolId).get();
  const schoolData = schoolSnap.data() ?? {};
  const tz = String(schoolData.timezone ?? DEFAULT_TIMEZONE);
  const isCountingDay = buildIsCountingDay(parseTermDates(schoolData.termDates));

  const beforeCounted = extractCountedFields(before, tz);
  const afterCounted = extractCountedFields(after, tz);

  // No transition affects stats — bail.
  if (!beforeCounted && !afterCounted) return;

  const studentSnap = await studentRef.get();
  const stats = studentSnap.data()?.stats ?? {};

  // Self-heal: first-ever trigger for this student in incremental mode.
  // Run the full recompute once to seed the readingDates array.
  if (!Array.isArray(stats.readingDates)) {
    await reconcileStudentStats(schoolId, studentId);
    return;
  }

  const readingDates = new Set<string>(stats.readingDates as string[]);

  // Date may disappear if either: (a) log was counted before and isn't now,
  // or (b) log moved to a different date. Only remove if no other counted
  // log for this student is on that date.
  if (
    beforeCounted &&
    (!afterCounted || beforeCounted.localDate !== afterCounted.localDate)
  ) {
    const dayStart = new Date(`${beforeCounted.localDate}T00:00:00Z`);
    const dayEnd = new Date(`${beforeCounted.localDate}T23:59:59.999Z`);
    const others = await db
      .collection(`schools/${schoolId}/readingLogs`)
      .where("studentId", "==", studentId)
      .where("status", "in", COUNTED_STATUSES)
      .where("date", ">=", admin.firestore.Timestamp.fromDate(dayStart))
      .where("date", "<=", admin.firestore.Timestamp.fromDate(dayEnd))
      .where(admin.firestore.FieldPath.documentId(), "!=", change.before.id)
      .limit(1)
      .count()
      .get();
    if (others.data().count === 0) {
      readingDates.delete(beforeCounted.localDate);
    }
  }

  if (afterCounted) {
    readingDates.add(afterCounted.localDate);
  }

  const deltaMinutes =
    (afterCounted?.minutes ?? 0) - (beforeCounted?.minutes ?? 0);
  const deltaBooks =
    (afterCounted?.books ?? 0) - (beforeCounted?.books ?? 0);

  const today = localDateString(new Date(), tz);
  const {currentStreak, restDaysRemaining} =
    computeGentleStreak(readingDates, today, MAX_REST_DAYS, isCountingDay);
  const longestStreak = Math.max(
    Number(stats.longestStreak) || 0,
    computeLongestStreak(readingDates),
    currentStreak,
  );

  const newTotalMinutes = Math.max(0, (Number(stats.totalMinutesRead) || 0) + deltaMinutes);
  const newTotalBooks = Math.max(0, (Number(stats.totalBooksRead) || 0) + deltaBooks);
  const totalReadingDays = readingDates.size;
  const averageMinutesPerDay =
    totalReadingDays > 0 ? newTotalMinutes / totalReadingDays : 0;

  // lastReadingDate: max(prior, after). On deletes we leave it alone — the
  // weekly reconciler will correct any drift if a delete trimmed the
  // most-recent log.
  let lastReadingDate = stats.lastReadingDate ?? null;
  if (afterCounted) {
    if (
      !lastReadingDate ||
      afterCounted.date.toMillis() > lastReadingDate.toMillis()
    ) {
      lastReadingDate = afterCounted.date;
    }
  }

  await studentRef.update({
    "stats.totalMinutesRead": newTotalMinutes,
    "stats.totalBooksRead": newTotalBooks,
    "stats.currentStreak": currentStreak,
    "stats.longestStreak": longestStreak,
    "stats.lastReadingDate": lastReadingDate,
    "stats.averageMinutesPerDay": Math.round(averageMinutesPerDay * 10) / 10,
    "stats.totalReadingDays": totalReadingDays,
    "stats.last30DaysCount": countInWindow(readingDates, today, 30),
    "stats.last50DaysCount": countInWindow(readingDates, today, 50),
    "stats.restDaysRemaining": restDaysRemaining,
    "stats.readingDates": [...readingDates].sort(),
    "stats.lastUpdated": admin.firestore.FieldValue.serverTimestamp(),
  });
}

// ──────────────────────────────────────────────────────────────────────
// Class stats
// ──────────────────────────────────────────────────────────────────────

const FIRESTORE_IN_LIMIT = 30;

function chunk<T>(arr: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

/**
 * Full recompute of class stats by re-reading every counted log for every
 * student in the class. Equivalent to the legacy `updateClassStats` body.
 * @param {string} schoolId The school document ID.
 * @param {string} classId The class document ID within the school.
 * @return {Promise<void>} Resolves when the class doc is updated.
 */
export async function reconcileClassStats(
  schoolId: string,
  classId: string,
): Promise<void> {
  const db = admin.firestore();
  const classRef = db.doc(`schools/${schoolId}/classes/${classId}`);
  const classSnap = await classRef.get();
  if (!classSnap.exists) return;

  const classData = classSnap.data() ?? {};
  const classStudentIds: string[] = Array.isArray(classData.studentIds) ?
    classData.studentIds.filter((id: unknown): id is string => typeof id === "string") :
    [];

  if (classStudentIds.length === 0) {
    await classRef.update({
      "stats.totalMinutesRead": 0,
      "stats.totalBooksRead": 0,
      "stats.activeStudents": 0,
      "stats.activeStudentIds": [],
      "stats.lastUpdated": admin.firestore.FieldValue.serverTimestamp(),
    });
    return;
  }

  let totalMinutes = 0;
  let totalBooks = 0;
  const activeStudentIds = new Set<string>();

  for (const studentBatch of chunk(classStudentIds, FIRESTORE_IN_LIMIT)) {
    const logsSnap = await db
      .collection(`schools/${schoolId}/readingLogs`)
      .where("studentId", "in", studentBatch)
      .where("status", "in", COUNTED_STATUSES)
      .get();

    logsSnap.docs.forEach((doc) => {
      const data = doc.data();
      if (isInvalidatedLog(data)) return;
      totalMinutes += Number(data.minutesRead) || 0;
      totalBooks += Array.isArray(data.bookTitles) ? data.bookTitles.length : 0;
      if (typeof data.studentId === "string") activeStudentIds.add(data.studentId);
    });
  }

  await classRef.update({
    "stats.totalMinutesRead": totalMinutes,
    "stats.totalBooksRead": totalBooks,
    "stats.activeStudents": activeStudentIds.size,
    "stats.activeStudentIds": [...activeStudentIds].sort(),
    "stats.lastUpdated": admin.firestore.FieldValue.serverTimestamp(),
  });
}

/**
 * Incremental class stats. Reads the student doc (for classId) + class
 * doc, applies the per-log delta. Adds the student to activeStudentIds
 * on create, removes on delete (with single-count guard).
 * @param {functions.Change<admin.firestore.DocumentSnapshot>} change Trigger change snapshot.
 * @param {string} schoolId The school document ID from the trigger params.
 * @return {Promise<void>} Resolves when the class doc is updated.
 */
export async function applyClassStatsDelta(
  change: functions.Change<admin.firestore.DocumentSnapshot>,
  schoolId: string,
): Promise<void> {
  const before = change.before.exists ? (change.before.data() ?? null) : null;
  const after = change.after.exists ? (change.after.data() ?? null) : null;
  const log = after ?? before;
  if (!log) return;

  const studentId = log.studentId;
  if (!studentId || typeof studentId !== "string") return;

  const db = admin.firestore();
  const studentSnap = await db
    .doc(`schools/${schoolId}/students/${studentId}`)
    .get();
  const classId = studentSnap.data()?.classId;
  if (!classId || typeof classId !== "string") return;

  const classRef = db.doc(`schools/${schoolId}/classes/${classId}`);
  const classSnap = await classRef.get();
  if (!classSnap.exists) return;

  // Self-heal: if activeStudentIds isn't populated, fall back to full recompute.
  const stats = classSnap.data()?.stats ?? {};
  if (!Array.isArray(stats.activeStudentIds)) {
    await reconcileClassStats(schoolId, classId);
    return;
  }

  const beforeCounted =
    before && COUNTED_STATUSES.includes(String(before.status ?? "")) &&
    !isInvalidatedLog(before) ?
      {
        minutes: Number(before.minutesRead) || 0,
        books: Array.isArray(before.bookTitles) ? before.bookTitles.length : 0,
      } :
      null;
  const afterCounted =
    after && COUNTED_STATUSES.includes(String(after.status ?? "")) &&
    !isInvalidatedLog(after) ?
      {
        minutes: Number(after.minutesRead) || 0,
        books: Array.isArray(after.bookTitles) ? after.bookTitles.length : 0,
      } :
      null;

  if (!beforeCounted && !afterCounted) return;

  const deltaMinutes = (afterCounted?.minutes ?? 0) - (beforeCounted?.minutes ?? 0);
  const deltaBooks = (afterCounted?.books ?? 0) - (beforeCounted?.books ?? 0);

  const activeStudentIds = new Set<string>(stats.activeStudentIds as string[]);
  let activeStudentIdsChanged = false;

  if (afterCounted && !activeStudentIds.has(studentId)) {
    activeStudentIds.add(studentId);
    activeStudentIdsChanged = true;
  } else if (!afterCounted && beforeCounted) {
    // Removing the last counted log for this student in this class?
    const others = await db
      .collection(`schools/${schoolId}/readingLogs`)
      .where("studentId", "==", studentId)
      .where("status", "in", COUNTED_STATUSES)
      .where(admin.firestore.FieldPath.documentId(), "!=", change.before.id)
      .limit(1)
      .count()
      .get();
    if (others.data().count === 0 && activeStudentIds.has(studentId)) {
      activeStudentIds.delete(studentId);
      activeStudentIdsChanged = true;
    }
  }

  const newTotalMinutes = Math.max(0, (Number(stats.totalMinutesRead) || 0) + deltaMinutes);
  const newTotalBooks = Math.max(0, (Number(stats.totalBooksRead) || 0) + deltaBooks);

  const update: Record<string, unknown> = {
    "stats.totalMinutesRead": newTotalMinutes,
    "stats.totalBooksRead": newTotalBooks,
    "stats.lastUpdated": admin.firestore.FieldValue.serverTimestamp(),
  };
  if (activeStudentIdsChanged) {
    update["stats.activeStudents"] = activeStudentIds.size;
    update["stats.activeStudentIds"] = [...activeStudentIds].sort();
  }

  await classRef.update(update);
}

// ──────────────────────────────────────────────────────────────────────
// Reconciler — used by the weekly scheduled function
// ──────────────────────────────────────────────────────────────────────

/**
 * Iterate every student + class across every school and run the full
 * recompute path. Safety net for any drift in the incremental path.
 * Caller passes the page size + total cap so callers can use the same
 * helper from a one-off Cloud Run job or the weekly cron.
 * @param {object} opts Optional caps to keep the pass within the 540s function timeout.
 * @return {Promise<object>} Counts of docs reconciled before the budget was reached.
 */
export async function runReconcilePass(opts: {
  /** Cap total students reconciled per run (avoid 540s timeout). */
  studentBudget?: number;
  /** Cap total classes reconciled per run. */
  classBudget?: number;
}): Promise<{studentsProcessed: number; classesProcessed: number}> {
  const db = admin.firestore();
  const studentBudget = opts.studentBudget ?? 5000;
  const classBudget = opts.classBudget ?? 1000;

  let studentsProcessed = 0;
  let classesProcessed = 0;

  const schoolsSnap = await db.collection("schools").get();
  for (const schoolDoc of schoolsSnap.docs) {
    const schoolId = schoolDoc.id;

    if (studentsProcessed < studentBudget) {
      const studentsSnap = await db
        .collection(`schools/${schoolId}/students`)
        .get();
      for (const studentDoc of studentsSnap.docs) {
        if (studentsProcessed >= studentBudget) break;
        try {
          await reconcileStudentStats(schoolId, studentDoc.id);
          studentsProcessed++;
        } catch (err) {
          functions.logger.error("reconcileStudentStats failed", {
            schoolId, studentId: studentDoc.id,
            error: err instanceof Error ? err.message : String(err),
          });
        }
      }
    }

    if (classesProcessed < classBudget) {
      const classesSnap = await db
        .collection(`schools/${schoolId}/classes`)
        .get();
      for (const classDoc of classesSnap.docs) {
        if (classesProcessed >= classBudget) break;
        try {
          await reconcileClassStats(schoolId, classDoc.id);
          classesProcessed++;
        } catch (err) {
          functions.logger.error("reconcileClassStats failed", {
            schoolId, classId: classDoc.id,
            error: err instanceof Error ? err.message : String(err),
          });
        }
      }
    }
  }

  return {studentsProcessed, classesProcessed};
}
