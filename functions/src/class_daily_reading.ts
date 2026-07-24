import * as admin from "firebase-admin";
import * as crypto from "crypto";
import {DEFAULT_TIMEZONE} from "./access";
import {resolveOccurrenceDate} from "./dateUtils";
import {isInvalidatedLog} from "./stats_aggregation";

export const CLASS_DAILY_READING_SCHEMA_VERSION = 1;
export const CLASS_DAILY_READING_SHARDS = 8;
const COUNTED_STATUSES = new Set(["completed", "partial"]);

export interface DailyReadingProjection {
  classId: string;
  localDate: string;
  shard: number;
  studentId: string;
  minutes: number;
  teacherLogs: number;
}

interface StudentDailyMetric {
  logs: number;
  minutes: number;
  teacherLogs: number;
}

interface DailySummaryData {
  schemaVersion: number;
  classId: string;
  localDate: string;
  shard: number;
  logCount: number;
  totalMinutes: number;
  teacherLogCount: number;
  activeStudentCount: number;
  students: Record<string, StudentDailyMetric>;
}

function sha256(value: string): string {
  return crypto.createHash("sha256").update(value).digest("hex");
}

/**
 * Deterministically assigns all of a student's logs to one class/day shard.
 * @param {string} studentId Authoritative student document ID.
 * @return {number} Stable shard number in the configured range.
 */
export function dailyReadingShard(studentId: string): number {
  return parseInt(sha256(studentId).slice(0, 8), 16) %
    CLASS_DAILY_READING_SHARDS;
}

/**
 * Converts an authoritative reading log into its counted daily projection.
 * @param {FirebaseFirestore.DocumentData | undefined} data Source log data.
 * @param {string} timezone Owning school's IANA timezone.
 * @return {DailyReadingProjection | null} Counted projection or null.
 */
export function buildDailyReadingProjection(
  data: FirebaseFirestore.DocumentData | undefined,
  timezone: string,
): DailyReadingProjection | null {
  if (!data || isInvalidatedLog(data)) return null;
  if (!COUNTED_STATUSES.has(String(data.status ?? ""))) return null;
  const classId = typeof data.classId === "string" ? data.classId.trim() : "";
  const studentId =
    typeof data.studentId === "string" ? data.studentId.trim() : "";
  const date = data.date as admin.firestore.Timestamp | undefined;
  const minutes = Number(data.minutesRead);
  if (!classId || !studentId || !date || typeof date.toDate !== "function") {
    return null;
  }
  if (!Number.isInteger(minutes) || minutes < 1 || minutes > 240) return null;
  return {
    classId,
    localDate: resolveOccurrenceDate(data.occurredOn, date.toDate(), timezone),
    shard: dailyReadingShard(studentId),
    studentId,
    minutes,
    teacherLogs: data.loggedByRole === "teacher" ? 1 : 0,
  };
}

function projectionsEqual(
  left: DailyReadingProjection | null,
  right: DailyReadingProjection | null,
): boolean {
  if (left === null || right === null) return left === right;
  return left.classId === right.classId &&
    left.localDate === right.localDate &&
    left.shard === right.shard &&
    left.studentId === right.studentId &&
    left.minutes === right.minutes &&
    left.teacherLogs === right.teacherLogs;
}

function projectionFromState(
  data: FirebaseFirestore.DocumentData | undefined,
): DailyReadingProjection | null {
  if (!data) return null;
  const projection = {
    classId: String(data.classId ?? ""),
    localDate: String(data.localDate ?? ""),
    shard: Number(data.shard),
    studentId: String(data.studentId ?? ""),
    minutes: Number(data.minutes),
    teacherLogs: Number(data.teacherLogs),
  };
  if (!projection.classId || !/^\d{4}-\d{2}-\d{2}$/.test(projection.localDate)) {
    return null;
  }
  if (!Number.isInteger(projection.shard) ||
      projection.shard < 0 ||
      projection.shard >= CLASS_DAILY_READING_SHARDS ||
      !projection.studentId ||
      !Number.isInteger(projection.minutes) ||
      !Number.isInteger(projection.teacherLogs)) {
    return null;
  }
  return projection;
}

function bucketKey(projection: DailyReadingProjection): string {
  return sha256(
    `${projection.classId}\u0000${projection.localDate}\u0000${projection.shard}`,
  );
}

function emptySummary(projection: DailyReadingProjection): DailySummaryData {
  return {
    schemaVersion: CLASS_DAILY_READING_SCHEMA_VERSION,
    classId: projection.classId,
    localDate: projection.localDate,
    shard: projection.shard,
    logCount: 0,
    totalMinutes: 0,
    teacherLogCount: 0,
    activeStudentCount: 0,
    students: {},
  };
}

function parseSummary(
  data: FirebaseFirestore.DocumentData | undefined,
  fallback: DailyReadingProjection,
): DailySummaryData {
  const students: Record<string, StudentDailyMetric> = {};
  const rawStudents = data?.students;
  if (rawStudents && typeof rawStudents === "object") {
    for (const [studentId, raw] of Object.entries(rawStudents)) {
      if (!raw || typeof raw !== "object") continue;
      const metric = raw as Record<string, unknown>;
      const logs = Number(metric.logs);
      const minutes = Number(metric.minutes);
      const teacherLogs = Number(metric.teacherLogs);
      if (!Number.isInteger(logs) || logs <= 0) continue;
      students[studentId] = {
        logs,
        minutes: Number.isFinite(minutes) ? Math.max(0, minutes) : 0,
        teacherLogs:
          Number.isInteger(teacherLogs) ? Math.max(0, teacherLogs) : 0,
      };
    }
  }
  const parsed = emptySummary(fallback);
  parsed.students = students;
  parsed.logCount = Number(data?.logCount) || 0;
  parsed.totalMinutes = Number(data?.totalMinutes) || 0;
  parsed.teacherLogCount = Number(data?.teacherLogCount) || 0;
  parsed.activeStudentCount = Object.keys(students).length;
  return parsed;
}

/**
 * Applies a single prior/desired projection to one summary bucket.
 * @param {FirebaseFirestore.DocumentData | undefined} summary Existing bucket.
 * @param {DailyReadingProjection} bucket Bucket identity and fallback fields.
 * @param {DailyReadingProjection | null} prior Previously stored projection.
 * @param {DailyReadingProjection | null} desired Current source projection.
 * @return {DailySummaryData | null} Updated summary, or null when empty.
 */
export function applyDailyReadingDelta(
  summary: FirebaseFirestore.DocumentData | undefined,
  bucket: DailyReadingProjection,
  prior: DailyReadingProjection | null,
  desired: DailyReadingProjection | null,
): DailySummaryData | null {
  const next = parseSummary(summary, bucket);
  const apply = (projection: DailyReadingProjection, direction: 1 | -1) => {
    next.logCount += direction;
    next.totalMinutes += direction * projection.minutes;
    next.teacherLogCount += direction * projection.teacherLogs;
    const current = next.students[projection.studentId] ?? {
      logs: 0,
      minutes: 0,
      teacherLogs: 0,
    };
    const updated = {
      logs: current.logs + direction,
      minutes: current.minutes + direction * projection.minutes,
      teacherLogs: current.teacherLogs + direction * projection.teacherLogs,
    };
    if (updated.logs <= 0) {
      delete next.students[projection.studentId];
    } else {
      next.students[projection.studentId] = {
        logs: updated.logs,
        minutes: Math.max(0, updated.minutes),
        teacherLogs: Math.max(0, updated.teacherLogs),
      };
    }
  };

  if (prior && bucketKey(prior) === bucketKey(bucket)) apply(prior, -1);
  if (desired && bucketKey(desired) === bucketKey(bucket)) apply(desired, 1);
  next.activeStudentCount = Object.keys(next.students).length;
  next.logCount = Math.max(0, next.logCount);
  next.totalMinutes = Math.max(0, next.totalMinutes);
  next.teacherLogCount = Math.max(0, next.teacherLogCount);
  return next.logCount === 0 ? null : next;
}

const timezoneCache = new Map<string, {timezone: string; loadedAt: number}>();
const TIMEZONE_CACHE_MS = 60_000;

/**
 * Owning school's IANA timezone, cached ~60s per instance. Shared with the
 * reading-log validation/cleanup paths in index.ts / reading_log_cleanup.ts.
 * @param {string} schoolId School document ID.
 * @return {Promise<string>} IANA timezone (DEFAULT_TIMEZONE fallback).
 */
export async function schoolTimezone(schoolId: string): Promise<string> {
  const cached = timezoneCache.get(schoolId);
  if (cached && Date.now() - cached.loadedAt < TIMEZONE_CACHE_MS) {
    return cached.timezone;
  }
  const school = await admin.firestore().doc(`schools/${schoolId}`).get();
  const timezone = String(school.data()?.timezone ?? DEFAULT_TIMEZONE);
  timezoneCache.set(schoolId, {timezone, loadedAt: Date.now()});
  return timezone;
}

/**
 * Converges one reading log's projection and class/day summaries on the
 * current source document. Reading the current document (rather than trusting
 * event order) makes create/update/validation/delete retries idempotent.
 * @param {string} schoolId Owning school document ID.
 * @param {string} logId Source reading-log document ID.
 * @return {Promise<void>} Resolves after the projection converges.
 */
export async function syncReadingLogDailySummary(
  schoolId: string,
  logId: string,
): Promise<void> {
  const db = admin.firestore();
  const timezone = await schoolTimezone(schoolId);
  const logRef = db.doc(`schools/${schoolId}/readingLogs/${logId}`);
  const stateRef = db.doc(`schools/${schoolId}/readingLogSummaryState/${logId}`);

  await db.runTransaction(async (transaction) => {
    const [logSnap, stateSnap] = await transaction.getAll(logRef, stateRef);
    const desired = buildDailyReadingProjection(logSnap.data(), timezone);
    const prior = projectionFromState(stateSnap.data());
    if (projectionsEqual(prior, desired)) return;

    const buckets = new Map<string, DailyReadingProjection>();
    if (prior) buckets.set(bucketKey(prior), prior);
    if (desired) buckets.set(bucketKey(desired), desired);
    const bucketEntries = [...buckets.entries()];
    const summaryRefs = bucketEntries.map(([key]) =>
      db.doc(`schools/${schoolId}/classDailyReading/${key}`));
    const summarySnaps = summaryRefs.length > 0 ?
      await transaction.getAll(...summaryRefs) : [];

    bucketEntries.forEach(([, bucket], index) => {
      const updated = applyDailyReadingDelta(
        summarySnaps[index]?.data(),
        bucket,
        prior,
        desired,
      );
      if (updated === null) {
        transaction.delete(summaryRefs[index]);
      } else {
        transaction.set(summaryRefs[index], {
          ...updated,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    });

    if (desired === null) {
      transaction.delete(stateRef);
    } else {
      transaction.set(stateRef, {
        schemaVersion: CLASS_DAILY_READING_SCHEMA_VERSION,
        ...desired,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  });
}

export interface ClassDailyReadingReconcileResult {
  schools: number;
  logs: number;
  states: number;
  summaries: number;
}

async function runWithConcurrency<T>(
  values: T[],
  concurrency: number,
  worker: (value: T) => Promise<void>,
): Promise<void> {
  let cursor = 0;
  const runners = Array.from(
    {length: Math.min(concurrency, values.length)},
    async () => {
      while (cursor < values.length) {
        const value = values[cursor++];
        await worker(value);
      }
    },
  );
  await Promise.all(runners);
}

/**
 * Reconciles projections from authoritative logs, removes stale projection
 * state, then rebuilds every summary bucket exactly from the resulting state.
 * @param {string[] | undefined} requestedSchoolIds Optional school scope.
 * @return {Promise<ClassDailyReadingReconcileResult>} Aggregate pass counts.
 */
export async function reconcileClassDailyReadingPass(
  requestedSchoolIds?: string[],
): Promise<ClassDailyReadingReconcileResult> {
  const db = admin.firestore();
  const schoolIds = requestedSchoolIds ??
    (await db.collection("schools").select().get()).docs.map((doc) => doc.id);
  const result: ClassDailyReadingReconcileResult = {
    schools: 0,
    logs: 0,
    states: 0,
    summaries: 0,
  };

  for (const schoolId of schoolIds) {
    const school = db.doc(`schools/${schoolId}`);
    const logs = await school.collection("readingLogs").select().get();
    const initialStates = await school
      .collection("readingLogSummaryState").select().get();
    const ids = new Set([
      ...logs.docs.map((doc) => doc.id),
      ...initialStates.docs.map((doc) => doc.id),
    ]);
    await runWithConcurrency([...ids], 10, (logId) =>
      syncReadingLogDailySummary(schoolId, logId));

    const states = await school.collection("readingLogSummaryState").get();
    const expected = new Map<string, DailySummaryData>();
    for (const state of states.docs) {
      const projection = projectionFromState(state.data());
      if (!projection) continue;
      const key = bucketKey(projection);
      const updated = applyDailyReadingDelta(
        expected.get(key), projection, null, projection,
      );
      if (updated) expected.set(key, updated);
    }

    const summaries = await school.collection("classDailyReading").get();
    const existingIds = new Set(summaries.docs.map((doc) => doc.id));
    const writer = db.bulkWriter();
    for (const [id, summary] of expected.entries()) {
      writer.set(school.collection("classDailyReading").doc(id), {
        ...summary,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      existingIds.delete(id);
    }
    for (const staleId of existingIds) {
      writer.delete(school.collection("classDailyReading").doc(staleId));
    }
    await writer.close();

    result.schools++;
    result.logs += logs.size;
    result.states += states.size;
    result.summaries += expected.size;
  }
  return result;
}
