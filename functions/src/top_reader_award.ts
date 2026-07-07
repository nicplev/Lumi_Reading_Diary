import * as functions from "firebase-functions/v1";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import {
  buildIsCountingDay,
  localDateString,
  parseTermDates,
  shiftDays,
} from "./dateUtils";
import {DEFAULT_TIMEZONE} from "./access";

/**
 * Weekly "Top Reader" award. Every Monday it looks at the week that just ended
 * and, for each class that has opted in (`settings.awards.topReader.enabled`),
 * assigns the gold award character to the student who read the most minutes —
 * writing `autoAward` to that student's doc (server-only; the app renders it
 * via StudentModel.displayCharacterId) and clearing the previous holder. The
 * winner keeps gold through the coming week.
 *
 * Only reading logs with a counted status are tallied, matching the stats
 * aggregation, and only currently-active students in the class can win.
 */

const COUNTED_STATUSES = new Set(["completed", "partial"]);
const STUDENT_BATCH = 400;
const GOLD_CHARACTER_ID = "gold_lumi";
const DEFAULT_TOP_READER_NAME = "Reader of the Week";

interface StudentTotals {
  minutes: number;
  logs: number;
}

/**
 * Pick the winning studentId from per-student totals, or null when nobody read.
 * Ties break by more minutes, then more logs, then lowest studentId (stable).
 * @param {Map<string, StudentTotals>} totals Minutes+logs keyed by studentId.
 * @return {string | null} The winning studentId, or null.
 */
export function pickTopReader(totals: Map<string, StudentTotals>): string | null {
  let winner: string | null = null;
  let best: StudentTotals = {minutes: 0, logs: 0};
  for (const id of [...totals.keys()].sort()) {
    const t = totals.get(id);
    if (!t || t.minutes <= 0) continue;
    if (
      t.minutes > best.minutes ||
      (t.minutes === best.minutes && t.logs > best.logs)
    ) {
      best = t;
      winner = id;
    }
  }
  return winner;
}

/**
 * The previous ISO week (Monday..Sunday) as local date strings in `tz`,
 * relative to `now`. `weekOf` is that Monday's date.
 * @param {Date} now The instant the job runs.
 * @param {string} tz The IANA timezone the school week is measured in.
 * @return {{firstDay: string, lastDay: string, weekOf: string}} Week bounds.
 */
export function previousWeek(
  now: Date,
  tz: string,
): {firstDay: string; lastDay: string; weekOf: string} {
  const todayStr = localDateString(now, tz);
  // Weekday of todayStr (0=Sun..6=Sat), day-stable via a noon-UTC anchor.
  const weekday = new Date(`${todayStr}T12:00:00Z`).getUTCDay();
  const mondayDelta = weekday === 0 ? -6 : 1 - weekday;
  const thisMonday = shiftDays(todayStr, mondayDelta);
  return {
    firstDay: shiftDays(thisMonday, -7),
    lastDay: shiftDays(thisMonday, -1),
    weekOf: shiftDays(thisMonday, -7),
  };
}

/**
 * Whether any day in the inclusive [firstDay, lastDay] range is a counting
 * (in-term) day. Used to skip crowning a Top Reader for a week that falls
 * entirely inside the school holidays.
 * @param {string} firstDay First day of the range, "YYYY-MM-DD".
 * @param {string} lastDay Last day of the range, "YYYY-MM-DD".
 * @param {function(string): boolean} isCountingDay The counting-day predicate.
 * @return {boolean} True if the range contains at least one counting day.
 */
export function weekContainsCountingDay(
  firstDay: string,
  lastDay: string,
  isCountingDay: (d: string) => boolean,
): boolean {
  for (let d = firstDay; d <= lastDay; d = shiftDays(d, 1)) {
    if (isCountingDay(d)) return true;
  }
  return false;
}

export const topReaderAward = onSchedule(
  {
    schedule: "0 5 * * 1", // Mondays 05:00 (tz below)
    timeZone: DEFAULT_TIMEZONE, // Australia/Sydney
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const db = admin.firestore();
    const now = new Date();

    let batch = db.batch();
    let inBatch = 0;
    let cleared = 0;
    let awarded = 0;
    const flush = async (force = false) => {
      if (inBatch >= STUDENT_BATCH || (force && inBatch > 0)) {
        await batch.commit();
        batch = db.batch();
        inBatch = 0;
      }
    };

    const schools = await db.collection("schools").get();
    for (const school of schools.docs) {
      // The week is measured in the SCHOOL's own timezone so e.g. a
      // Sunday-evening log in Perth never slips into Sydney's Monday. The
      // cron fire time stays pinned to Sydney — by 05:00 AEST it is already
      // Monday morning everywhere in Australia.
      const rawTz = school.get("timezone");
      const tz =
        typeof rawTz === "string" && rawTz.length > 0 ? rawTz : DEFAULT_TIMEZONE;
      const {firstDay, lastDay, weekOf} = previousWeek(now, tz);

      // If the school has term dates configured and the whole week fell in
      // the holidays, skip it entirely: no award is crowned for an empty
      // holiday week and the current holder keeps gold through the break.
      const termDates = parseTermDates(school.get("termDates"));
      if (
        termDates.length > 0 &&
        !weekContainsCountingDay(firstDay, lastDay, buildIsCountingDay(termDates))
      ) {
        continue;
      }

      // Generous UTC query window (±margin) so no local-week log is missed
      // regardless of tz offset; precise membership is decided in memory by
      // the local date string.
      const queryStart = admin.firestore.Timestamp.fromDate(
        new Date(`${shiftDays(firstDay, -1)}T00:00:00Z`),
      );
      const queryEnd = admin.firestore.Timestamp.fromDate(
        new Date(`${shiftDays(lastDay, 2)}T00:00:00Z`),
      );

      const studentsCol = school.ref.collection("students");
      const logsCol = school.ref.collection("readingLogs");
      let classes;
      try {
        classes = await school.ref
          .collection("classes")
          .where("isActive", "==", true)
          .get();
      } catch (err) {
        functions.logger.error("topReaderAward: classes read failed", {
          school: school.id,
          error: err instanceof Error ? err.message : String(err),
        });
        continue;
      }

      for (const cls of classes.docs) {
        try {
          const settings = (cls.data().settings ?? {}) as Record<string, unknown>;
          const awards = (settings.awards ?? {}) as Record<string, unknown>;
          const topReader = (awards.topReader ?? {}) as Record<string, unknown>;
          const enabled = topReader.enabled === true;
          const rawName =
            typeof topReader.name === "string" ? topReader.name.trim() : "";
          const name = rawName.length > 0 ? rawName : DEFAULT_TOP_READER_NAME;

          const roster = await studentsCol
            .where("classId", "==", cls.id)
            .where("isActive", "==", true)
            .get();
          const rosterIds = new Set(roster.docs.map((d) => d.id));
          const currentHolders = roster.docs.filter(
            (d) => d.get("autoAward") != null,
          );

          let winnerId: string | null = null;
          if (enabled) {
            const logs = await logsCol
              .where("classId", "==", cls.id)
              .where("date", ">=", queryStart)
              .where("date", "<=", queryEnd)
              .get();
            const totals = new Map<string, StudentTotals>();
            for (const log of logs.docs) {
              const d = log.data();
              if (!COUNTED_STATUSES.has(d.status)) continue;
              const dt = d.date?.toDate?.();
              if (!dt) continue;
              const ds = localDateString(dt, tz);
              if (ds < firstDay || ds > lastDay) continue;
              const sid = d.studentId as string | undefined;
              if (!sid || !rosterIds.has(sid)) continue;
              const cur = totals.get(sid) ?? {minutes: 0, logs: 0};
              cur.minutes += typeof d.minutesRead === "number" ? d.minutesRead : 0;
              cur.logs += 1;
              totals.set(sid, cur);
            }
            winnerId = pickTopReader(totals);
          }

          // Clear every current holder that isn't the (possibly unchanged) winner.
          for (const holder of currentHolders) {
            if (holder.id === winnerId) continue;
            batch.update(holder.ref, {
              autoAward: admin.firestore.FieldValue.delete(),
            });
            inBatch++;
            cleared++;
            await flush();
          }
          // Assign / refresh the winner.
          if (winnerId) {
            batch.update(studentsCol.doc(winnerId), {
              autoAward: {
                characterId: GOLD_CHARACTER_ID,
                name,
                weekOf,
                awardedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
            });
            inBatch++;
            awarded++;
            await flush();
          }
        } catch (err) {
          functions.logger.error("topReaderAward: class failed", {
            school: school.id,
            classId: cls.id,
            error: err instanceof Error ? err.message : String(err),
          });
        }
      }
    }

    await flush(true);
    functions.logger.info("topReaderAward complete", {
      awarded,
      cleared,
    });
  },
);
