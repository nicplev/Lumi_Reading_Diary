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
import {errorCodeForLog} from "./log_safety";
import * as functions from "firebase-functions/v1";
import {
  MAX_REST_DAYS,
  buildIsCountingDay,
  computeGentleStreak,
  computeLongestStreak,
  countInWindow,
  localDateUtcRange,
  localDateString,
  resolveOccurrenceDate,
  parseTermDates,
} from "./dateUtils";
import {DEFAULT_TIMEZONE} from "./access";
import {
  applyFeelingsDelta,
  buildLatestParentComment,
  extractParentCommentContent,
  recomputeStudentViewAggregates,
  resolveParentName,
  viewAggregatesRelevantChange,
} from "./student_view_aggregates";

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
 *
 * Exported for unit tests — production callers are the delta path below.
 * @param {FirebaseFirestore.DocumentData | null} logData Snapshot data.
 * @param {string} tz Owning school's IANA timezone.
 * @return {CountedLogFields | null} Contribution, or null if uncounted.
 */
export function extractCountedFields(
  logData: FirebaseFirestore.DocumentData | null,
  tz: string,
): CountedLogFields | null {
  if (!logData) return null;
  const status = String(logData.status ?? "");
  if (!COUNTED_STATUSES.includes(status)) return null;
  if (isInvalidatedLog(logData)) return null;
  const date = logData.date as admin.firestore.Timestamp | undefined;
  if (!date) return null;
  const localDate = resolveOccurrenceDate(logData.occurredOn, date.toDate(), tz);
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

  // View aggregates (feelingsByDay / latestParentComment) also hang off this
  // trigger: a feeling or parent-comment edit must recompute even when no
  // stat field moved. The two hot wasted firings this guard exists for
  // (validation stamps, comment-thread mirrors) touch neither, so they are
  // still skipped.
  if (viewAggregatesRelevantChange(b, a)) return false;

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
    // occurredOn feeds the day bucket (resolveOccurrenceDate); rules make it
    // immutable, but the guard stays correct even for Admin-SDK edits.
    (b.occurredOn ?? null) === (a.occurredOn ?? null) &&
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
 * @param {FirebaseFirestore.DocumentData} prefetchedSchoolData Optional
 *   already-read school doc data (tz + termDates) to avoid a re-read.
 * @return {Promise<void>} Resolves when the student doc is updated.
 */
export async function reconcileStudentStats(
  schoolId: string,
  studentId: string,
  prefetchedSchoolData?: FirebaseFirestore.DocumentData,
): Promise<void> {
  const db = admin.firestore();
  const studentRef = db.doc(`schools/${schoolId}/students/${studentId}`);

  const logsSnap = await db
    .collection(`schools/${schoolId}/readingLogs`)
    .where("studentId", "==", studentId)
    .where("status", "in", COUNTED_STATUSES)
    .get();

  // Callers that already hold the school doc (the weekly reconciler pages
  // through schools; the delta path's self-heal just read it) pass it in so
  // a pass over N students doesn't re-read the same school doc N times.
  const schoolData = prefetchedSchoolData ??
    ((await db.collection("schools").doc(schoolId).get()).data() ?? {});
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
      readingDatesSet.add(resolveOccurrenceDate(data.occurredOn, ts.toDate(), tz));
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

  // View aggregates ride the same recompute so the weekly reconciler,
  // self-heal path and backfill all repair them alongside the stats.
  const aggregates =
    await recomputeStudentViewAggregates(db, schoolId, studentId, tz);

  await studentRef.update({
    "feelingsByDay": aggregates.feelingsByDay,
    "latestParentComment": aggregates.latestParentComment,
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
  const aggregatesRelevant = viewAggregatesRelevantChange(before, after);

  // Neither the stats nor the view aggregates can change — bail.
  if (!beforeCounted && !afterCounted && !aggregatesRelevant) return;

  const today = localDateString(new Date(), tz);
  const changedLogId = change.after.exists ? change.after.id : change.before.id;

  // ── Pre-transaction reads ────────────────────────────────────────────
  // Everything below reads collections OTHER than the student doc, so it is
  // resolved before the transaction opens: a Firestore transaction must issue
  // all of its reads through `tx`, and re-running these on every retry would
  // multiply the read cost. None of them depend on the student's current
  // stats, only on the log change itself.

  // Date may disappear if either: (a) log was counted before and isn't now,
  // or (b) log moved to a different date. Only drop it if no other counted
  // log for this student shares that BUCKET day. A log's bucket day is
  // resolveOccurrenceDate(occurredOn ?? date), so membership needs two
  // probes: logs whose timestamp lands in the day's UTC range (filtered
  // per-doc, since a backdated log's timestamp can sit in the range while
  // bucketing to the previous day) and logs explicitly backdated INTO the
  // day (occurredOn == day, timestamp elsewhere). Both probes only run on
  // the rare drop path; per-student-per-day volume keeps them tiny.
  let dropBeforeDate = false;
  if (
    beforeCounted &&
    (!afterCounted || beforeCounted.localDate !== afterCounted.localDate)
  ) {
    const day = beforeCounted.localDate;
    const {startInclusive, endExclusive} = localDateUtcRange(day, tz);
    const inRange = await db
      .collection(`schools/${schoolId}/readingLogs`)
      .where("studentId", "==", studentId)
      .where("status", "in", COUNTED_STATUSES)
      .where("date", ">=", admin.firestore.Timestamp.fromDate(startInclusive))
      .where("date", "<", admin.firestore.Timestamp.fromDate(endExclusive))
      .where(admin.firestore.FieldPath.documentId(), "!=", change.before.id)
      .select("date", "occurredOn", "validationStatus")
      .get();
    const rangeHolds = inRange.docs.some((doc) => {
      const data = doc.data();
      if (isInvalidatedLog(data)) return false;
      const ts = data.date as admin.firestore.Timestamp | undefined;
      if (!ts) return false;
      return resolveOccurrenceDate(data.occurredOn, ts.toDate(), tz) === day;
    });
    let backdatedHolds = false;
    if (!rangeHolds) {
      const backdated = await db
        .collection(`schools/${schoolId}/readingLogs`)
        .where("studentId", "==", studentId)
        .where("status", "in", COUNTED_STATUSES)
        .where("occurredOn", "==", day)
        .where(admin.firestore.FieldPath.documentId(), "!=", change.before.id)
        .select("validationStatus")
        .get();
      backdatedHolds = backdated.docs.some((doc) =>
        !isInvalidatedLog(doc.data()));
    }
    dropBeforeDate = !rangeHolds && !backdatedHolds;
  }

  // If this write removes the student's most-recent counted log (a delete, or a
  // counted→uncounted flip on the newest log), `stats.lastReadingDate` would go
  // stale. Resolve the next-most-recent counted log now (pre-transaction, since
  // it is a collection query), so the transaction can correct the field instead
  // of leaving it for the weekly reconciler. `undefined` = "leave it alone";
  // `null` = "no counted logs remain". Only queried when the write drops a
  // counted log, keeping the common create/update path at zero extra reads.
  let replacementLastReadingDate:
    admin.firestore.Timestamp | null | undefined = undefined;
  if (beforeCounted && !afterCounted) {
    const newest = await db
      .collection(`schools/${schoolId}/readingLogs`)
      .where("studentId", "==", studentId)
      .where("status", "in", COUNTED_STATUSES)
      .where(admin.firestore.FieldPath.documentId(), "!=", change.before.id)
      .orderBy("date", "desc")
      .limit(1)
      .get();
    replacementLastReadingDate = newest.empty ?
      null :
      (newest.docs[0].data().date as admin.firestore.Timestamp);
  }

  // View-aggregate inputs that need I/O. Which one the transaction actually
  // uses depends on the stored `latestParentComment`, which isn't known until
  // the transactional read — so resolve whichever branch could apply. The two
  // conditions are mutually exclusive on `afterContent`, so at most one runs.
  const afterContent = extractParentCommentContent(after);
  const afterDate = after?.date as admin.firestore.Timestamp | undefined;
  let parentName = "Parent"; // resolveParentName's own fallback
  let fallbackLatestComment: unknown = undefined;
  if (aggregatesRelevant) {
    if (after && afterContent && afterDate) {
      parentName = await resolveParentName(
        db, schoolId,
        typeof after.parentId === "string" ? after.parentId : null,
      );
    } else {
      const recomputed =
        await recomputeStudentViewAggregates(db, schoolId, studentId, tz);
      fallbackLatestComment = recomputed.latestParentComment;
    }
  }

  // ── Transactional read-modify-write ──────────────────────────────────
  // The stats are an accumulator: read totals, add a delta, write back. Doing
  // that non-transactionally loses increments whenever two logs for the same
  // student are written close together — a batched import, or an offline
  // parent whose queued logs all flush on reconnect. Firestore retries the
  // transaction on contention, so concurrent triggers serialise instead of
  // clobbering each other.
  let needsReconcile = false;

  await db.runTransaction(async (tx) => {
    const studentSnap = await tx.get(studentRef);
    const studentData = studentSnap.data() ?? {};
    const stats = studentData.stats ?? {};

    // Self-heal: first-ever trigger for this student in incremental mode.
    // reconcileStudentStats does its own writes, so it can't run inside the
    // transaction — flag it and run it after this one commits.
    if (!Array.isArray(stats.readingDates)) {
      needsReconcile = true;
      return;
    }

    // ── View aggregates (feelingsByDay / latestParentComment) ───────────
    const aggregateUpdates:
      FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> = {};
    if (aggregatesRelevant) {
      const storedFeelings =
        (studentData.feelingsByDay as
          Record<string, Record<string, number>> | undefined) ?? {};
      aggregateUpdates["feelingsByDay"] =
        applyFeelingsDelta(storedFeelings, before, after, tz, today);

      const stored = studentData.latestParentComment as
        {logId?: string; date?: admin.firestore.Timestamp} | null | undefined;

      if (
        after && afterContent && afterDate &&
        (!stored?.date || afterDate.toMillis() >= stored.date.toMillis() ||
          stored.logId === changedLogId)
      ) {
        // Newest comment (or an edit to the currently-stored one) — set it.
        aggregateUpdates["latestParentComment"] =
          buildLatestParentComment(changedLogId, after, parentName);
      } else if (
        stored?.logId === changedLogId && (!after || !afterContent) &&
        fallbackLatestComment !== undefined
      ) {
        // The stored latest lost its content (or was deleted) — the bounded
        // recompute above found the next-newest commented log.
        aggregateUpdates["latestParentComment"] = fallbackLatestComment;
      }
    }

    // Aggregate-only writes (e.g. a feeling edit on an uncounted log) skip
    // the stats math entirely.
    if (!beforeCounted && !afterCounted) {
      if (Object.keys(aggregateUpdates).length > 0) {
        tx.update(studentRef, aggregateUpdates);
      }
      return;
    }

    const readingDates = new Set<string>(stats.readingDates as string[]);
    if (dropBeforeDate && beforeCounted) {
      readingDates.delete(beforeCounted.localDate);
    }
    if (afterCounted) {
      readingDates.add(afterCounted.localDate);
    }

    const deltaMinutes =
      (afterCounted?.minutes ?? 0) - (beforeCounted?.minutes ?? 0);
    const deltaBooks =
      (afterCounted?.books ?? 0) - (beforeCounted?.books ?? 0);

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

    // lastReadingDate: on a counted create/update it is max(prior, after). On a
    // delete (no counted `after`) it becomes the newest remaining counted log's
    // date, resolved pre-transaction above — `null` when none remain. Correct
    // immediately rather than waiting for the weekly reconciler.
    let lastReadingDate = stats.lastReadingDate ?? null;
    if (afterCounted) {
      if (
        !lastReadingDate ||
        afterCounted.date.toMillis() > lastReadingDate.toMillis()
      ) {
        lastReadingDate = afterCounted.date;
      }
    } else if (replacementLastReadingDate !== undefined) {
      lastReadingDate = replacementLastReadingDate;
    }

    tx.update(studentRef, {
      ...aggregateUpdates,
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
  });

  if (needsReconcile) {
    await reconcileStudentStats(schoolId, studentId, schoolData);
  }
}

// ──────────────────────────────────────────────────────────────────────
// Class stats
// ──────────────────────────────────────────────────────────────────────

// Firestore permits at most 30 disjunctions after query normalization. Class
// aggregation combines `studentId in [...]` with `status in [completed,
// partial]`, so each student ID consumes two disjunctions. Batching 30 student
// IDs produced 60 and caused the weekly reconciler to silently skip larger
// classes while the overall scheduled run still completed.
const FIRESTORE_MAX_DISJUNCTIONS = 30;
const CLASS_AGGREGATION_STUDENT_BATCH_SIZE =
  Math.floor(FIRESTORE_MAX_DISJUNCTIONS / COUNTED_STATUSES.length);

function chunk<T>(arr: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

/**
 * Split class student IDs into batches safe for the compound `in` query used
 * by both the incremental self-heal and legacy full recompute paths.
 * @param {string[]} studentIds Student document IDs in the class.
 * @return {Array<Array<string>>} Safe student ID batches.
 */
export function classAggregationStudentBatches(
  studentIds: string[],
): string[][] {
  return chunk(studentIds, CLASS_AGGREGATION_STUDENT_BATCH_SIZE);
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

  for (const studentBatch of classAggregationStudentBatches(classStudentIds)) {
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

  // Pre-transaction read: does this student still have any counted log after
  // this change? Reads readingLogs, not the class doc, so it stays outside the
  // transaction (see applyStudentStatsDelta for the full rationale).
  let studentHasNoRemainingLogs = false;
  if (!afterCounted && beforeCounted) {
    const others = await db
      .collection(`schools/${schoolId}/readingLogs`)
      .where("studentId", "==", studentId)
      .where("status", "in", COUNTED_STATUSES)
      .where(admin.firestore.FieldPath.documentId(), "!=", change.before.id)
      .limit(1)
      .count()
      .get();
    studentHasNoRemainingLogs = others.data().count === 0;
  }

  // Class totals accumulate the same way student stats do, so they lose
  // increments under the same concurrency. Every log written for any student
  // in the class contends here, making this the hotter of the two documents.
  let needsReconcile = false;

  await db.runTransaction(async (tx) => {
    const classSnap = await tx.get(classRef);
    if (!classSnap.exists) return;

    // Self-heal: if activeStudentIds isn't populated, fall back to full
    // recompute (which writes, so it runs after this transaction commits).
    const stats = classSnap.data()?.stats ?? {};
    if (!Array.isArray(stats.activeStudentIds)) {
      needsReconcile = true;
      return;
    }

    const activeStudentIds = new Set<string>(stats.activeStudentIds as string[]);
    let activeStudentIdsChanged = false;

    if (afterCounted && !activeStudentIds.has(studentId)) {
      activeStudentIds.add(studentId);
      activeStudentIdsChanged = true;
    } else if (
      studentHasNoRemainingLogs && activeStudentIds.has(studentId)
    ) {
      activeStudentIds.delete(studentId);
      activeStudentIdsChanged = true;
    }

    const newTotalMinutes = Math.max(0, (Number(stats.totalMinutesRead) || 0) + deltaMinutes);
    const newTotalBooks = Math.max(0, (Number(stats.totalBooksRead) || 0) + deltaBooks);

    const update:
      FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> = {
        "stats.totalMinutesRead": newTotalMinutes,
        "stats.totalBooksRead": newTotalBooks,
        "stats.lastUpdated": admin.firestore.FieldValue.serverTimestamp(),
      };
    if (activeStudentIdsChanged) {
      update["stats.activeStudents"] = activeStudentIds.size;
      update["stats.activeStudentIds"] = [...activeStudentIds].sort();
    }

    tx.update(classRef, update);
  });

  if (needsReconcile) {
    await reconcileClassStats(schoolId, classId);
  }
}

// ──────────────────────────────────────────────────────────────────────
// Reconciler — used by the weekly scheduled function
// ──────────────────────────────────────────────────────────────────────

/** Resume position for a paged reconcile: the last doc processed. */
interface ReconcileCursorPos {
  schoolId: string;
  docId: string;
}

/** Docs fetched per page while reconciling (IDs only via select()). */
const RECONCILE_PAGE = 300;

const reconcileCursorDoc = () =>
  admin.firestore().doc("platformConfig/statsReconcileCursor");

/**
 * Parses one cursor position out of the cursor doc, tolerating a missing
 * doc / field / malformed shape (all mean "start from the beginning").
 * @param {FirebaseFirestore.DocumentData | undefined} data Cursor doc data.
 * @param {string} key Which cursor to read ("student" | "class").
 * @return {ReconcileCursorPos | null} Position, or null for a fresh start.
 */
function readCursorPos(
  data: FirebaseFirestore.DocumentData | undefined,
  key: "student" | "class",
): ReconcileCursorPos | null {
  const raw = data?.[key];
  if (
    !raw ||
    typeof raw.schoolId !== "string" ||
    typeof raw.docId !== "string"
  ) {
    return null;
  }
  return {schoolId: raw.schoolId, docId: raw.docId};
}

/**
 * Pages through `schools/{sid}/{sub}` doc IDs across all schools, resuming
 * after `cursor`, invoking `fn` per doc until `budget` docs are processed.
 * Pages fetch IDs only (select()) and never read past the budget — the old
 * implementation read ENTIRE student/class collections regardless of budget
 * and always restarted from the first school, so once the population
 * outgrew the budget the tail schools were never reconciled.
 * @param {FirebaseFirestore.QueryDocumentSnapshot[]} schools Schools in
 *   documentId order (the order the cursor is defined against).
 * @param {string} sub Subcollection to page ("students" | "classes").
 * @param {ReconcileCursorPos | null} cursor Resume position, if any.
 * @param {number} budget Max docs to process this run.
 * @param {Function} fn Reconcile callback for one doc.
 * @return {Promise<object>} Processed count + resume cursor (null = the
 *   whole population was covered; next run wraps to the start).
 */
async function pageAndReconcile(
  schools: FirebaseFirestore.QueryDocumentSnapshot[],
  sub: "students" | "classes",
  cursor: ReconcileCursorPos | null,
  budget: number,
  fn: (
    schoolDoc: FirebaseFirestore.QueryDocumentSnapshot,
    docId: string,
  ) => Promise<void>,
): Promise<{processed: number; next: ReconcileCursorPos | null}> {
  let processed = 0;
  let pendingCursor = cursor;

  for (const schoolDoc of schools) {
    let lastId: string | null = null;
    if (pendingCursor) {
      // Skip schools wholly before the cursor. If the cursor's school was
      // deleted, resume at the first school after it (lexicographic).
      if (schoolDoc.id < pendingCursor.schoolId) continue;
      if (schoolDoc.id === pendingCursor.schoolId) {
        lastId = pendingCursor.docId || null;
      }
      pendingCursor = null;
    }

    for (;;) {
      const remaining = budget - processed;
      if (remaining <= 0) {
        // Budget exhausted mid-population: resume here next run. (If the
        // school happened to be exactly finished, next run's startAfter
        // returns an empty page and moves on — one cheap wasted query.)
        return {
          processed,
          next: {schoolId: schoolDoc.id, docId: lastId ?? ""},
        };
      }
      const pageSize = Math.min(remaining, RECONCILE_PAGE);
      let query = schoolDoc.ref
        .collection(sub)
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(pageSize);
      if (lastId) query = query.startAfter(lastId);
      const page = await query.select().get();
      if (page.empty) break;

      for (const doc of page.docs) {
        try {
          await fn(schoolDoc, doc.id);
        } catch (err) {
          functions.logger.error(`reconcile ${sub} doc failed`, {
            errorCode: errorCodeForLog(err),
          });
        }
        processed++;
        lastId = doc.id;
      }
      if (page.size < pageSize) break; // school exhausted
    }
  }

  return {processed, next: null};
}

/**
 * Reconcile up to the budgeted number of students + classes, resuming from
 * where the previous run stopped (cursor persisted in
 * platformConfig/statsReconcileCursor). Safety net for any drift in the
 * incremental path: successive weekly runs now cover the WHOLE population
 * in budget-sized slices instead of re-reconciling the same first N docs
 * while starving the tail.
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

  const cursorSnap = await reconcileCursorDoc().get();
  const cursorData = cursorSnap.data();

  // Schools ordered by documentId so the cursor's notion of before/after
  // is stable across runs.
  const schoolsSnap = await db
    .collection("schools")
    .orderBy(admin.firestore.FieldPath.documentId())
    .get();
  const schools = schoolsSnap.docs;

  // schoolDoc.data() is already in hand from the schools query — pass it
  // through so reconcileStudentStats doesn't re-read the school doc for
  // every student in the school.
  const students = await pageAndReconcile(
    schools, "students", readCursorPos(cursorData, "student"), studentBudget,
    (schoolDoc, docId) =>
      reconcileStudentStats(schoolDoc.id, docId, schoolDoc.data()),
  );
  const classes = await pageAndReconcile(
    schools, "classes", readCursorPos(cursorData, "class"), classBudget,
    (schoolDoc, docId) => reconcileClassStats(schoolDoc.id, docId),
  );

  await reconcileCursorDoc().set({
    student: students.next, // null = wrapped; next run starts fresh
    class: classes.next,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    studentsProcessed: students.processed,
    classesProcessed: classes.processed,
  };
}
