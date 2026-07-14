// Cron heartbeats for the super-admin dashboard's system-health panel.
//
// Before this, only 2 of the scheduled functions left any Firestore
// last-run marker — the rest were Cloud-Logging-only, so "is the cron
// alive?" had no cheap answer. Every cron now records
// {lastRunAt, lastStatus, note?} under its own key in
// opsMetrics/cronHeartbeats (one doc = one dashboard read; worst-case
// write rate is two every-5-minute crons, far below single-doc limits).

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

const HEARTBEAT_DOC = "opsMetrics/cronHeartbeats";

export type CronRunStatus = "ok" | "error" | "skipped";

/**
 * Records a cron run outcome. Fire-and-forget semantics: a heartbeat
 * write failure must never fail (or retry) the cron itself, so errors
 * are swallowed after logging.
 * @param {string} name The exported function name of the cron.
 * @param {CronRunStatus} status How the run ended.
 * @param {string=} note Optional short context (e.g. a skip reason).
 * @return {Promise<void>} Resolves once the write settles either way.
 */
export async function recordCronRun(
  name: string,
  status: CronRunStatus,
  note?: string,
): Promise<void> {
  try {
    await admin.firestore().doc(HEARTBEAT_DOC).set(
      {
        [name]: {
          lastRunAt: admin.firestore.FieldValue.serverTimestamp(),
          lastStatus: status,
          // Clear any stale note from a prior skipped/error run.
          note: note ?? admin.firestore.FieldValue.delete(),
        },
      },
      {merge: true},
    );
  } catch (err) {
    functions.logger.warn("opsHeartbeat.writeFailed", {
      name,
      status,
      error: err instanceof Error ? err.message : String(err),
    });
  }
}
