/**
 * Daily streak refresh.
 *
 * stats.currentStreak is only recomputed when a reading-log write fires the
 * stats trigger or when the weekly reconciler visits the student — nothing
 * refreshes it day to day. A streak that dies on a Monday therefore keeps
 * displaying its old value on every surface (parent home, progress screen,
 * widget, teacher dashboards) until the next log or the following Sunday.
 *
 * This pass closes that gap cheaply: one query per school for students whose
 * stored streak is > 0 (dead streaks self-prune from the query once written
 * to 0), recompute from the maintained stats.readingDates array — no
 * reading-log reads at all — and write back only the students whose numbers
 * actually changed. The rolling last30/last50 counts slide daily too, so they
 * are refreshed in the same write.
 *
 * Full-recompute correctness (totals, longestStreak, self-heal of a missing
 * readingDates array) stays with reconcileStudentStats / the weekly
 * reconciler; this pass deliberately touches nothing but the day-sensitive
 * fields.
 */

import * as admin from "firebase-admin";
import {
  MAX_REST_DAYS,
  buildIsCountingDay,
  computeGentleStreak,
  countInWindow,
  localDateString,
  parseTermDates,
} from "./dateUtils";
import {DEFAULT_TIMEZONE} from "./access";

/** Firestore batched-write ceiling, kept below the hard 500 limit. */
const WRITE_BATCH_SIZE = 400;

/**
 * Recomputes the day-sensitive stats fields for one student and returns the
 * fields that changed, or null when the stored values are already correct
 * (or the student has no readingDates array to recompute from — the weekly
 * reconciler owns seeding that).
 * @param {FirebaseFirestore.DocumentData} stats The student's stats map.
 * @param {string} today Today's local date ("YYYY-MM-DD") in the school tz.
 * @param {function(string): boolean} isCountingDay Term-date predicate for
 *   the student's school (see buildIsCountingDay).
 * @return {Record<string, number> | null} Changed stats fields keyed as
 *   Firestore update paths ("stats.currentStreak", ...), or null.
 */
export function computeStreakRefresh(
  stats: FirebaseFirestore.DocumentData,
  today: string,
  isCountingDay: (dateStr: string) => boolean,
): Record<string, number> | null {
  if (!Array.isArray(stats.readingDates)) return null;

  const readingDates = new Set<string>(
    (stats.readingDates as unknown[]).filter(
      (d): d is string => typeof d === "string",
    ),
  );

  const {currentStreak, restDaysRemaining} = computeGentleStreak(
    readingDates, today, MAX_REST_DAYS, isCountingDay,
  );

  const fresh: Record<string, number> = {
    "stats.currentStreak": currentStreak,
    "stats.restDaysRemaining": restDaysRemaining,
    "stats.last30DaysCount": countInWindow(readingDates, today, 30),
    "stats.last50DaysCount": countInWindow(readingDates, today, 50),
  };

  const changed: Record<string, number> = {};
  for (const [path, value] of Object.entries(fresh)) {
    const field = path.slice("stats.".length);
    if ((Number(stats[field]) || 0) !== value) changed[path] = value;
  }

  return Object.keys(changed).length > 0 ? changed : null;
}

/**
 * Runs the refresh across every school. One students query per school
 * (currentStreak > 0 — automatic single-field index), zero reading-log
 * reads, batched writes of only the changed students.
 * @return {Promise<{schools: number, checked: number, updated: number,
 *   skippedNoDates: number}>} Pass counters for logging/heartbeat.
 */
export async function runStreakRefreshPass(): Promise<{
  schools: number;
  checked: number;
  updated: number;
  skippedNoDates: number;
}> {
  const db = admin.firestore();
  const schoolsSnap = await db.collection("schools").get();

  let checked = 0;
  let updated = 0;
  let skippedNoDates = 0;

  let batch = db.batch();
  let inBatch = 0;
  const commitBatch = async () => {
    if (inBatch > 0) {
      await batch.commit();
      batch = db.batch();
      inBatch = 0;
    }
  };

  for (const schoolDoc of schoolsSnap.docs) {
    const schoolData = schoolDoc.data();
    const tz = String(schoolData.timezone ?? DEFAULT_TIMEZONE);
    const isCountingDay =
      buildIsCountingDay(parseTermDates(schoolData.termDates));
    const today = localDateString(new Date(), tz);

    const studentsSnap = await schoolDoc.ref
      .collection("students")
      .where("stats.currentStreak", ">", 0)
      .get();

    for (const studentDoc of studentsSnap.docs) {
      checked++;
      const stats = studentDoc.data().stats ?? {};
      if (!Array.isArray(stats.readingDates)) {
        // Pre-backfill doc — the weekly reconciler seeds readingDates.
        skippedNoDates++;
        continue;
      }
      const changed = computeStreakRefresh(stats, today, isCountingDay);
      if (!changed) continue;

      batch.update(studentDoc.ref, {
        ...changed,
        "stats.lastUpdated": admin.firestore.FieldValue.serverTimestamp(),
      });
      updated++;
      if (++inBatch >= WRITE_BATCH_SIZE) await commitBatch();
    }
  }

  await commitBatch();
  return {schools: schoolsSnap.size, checked, updated, skippedNoDates};
}
