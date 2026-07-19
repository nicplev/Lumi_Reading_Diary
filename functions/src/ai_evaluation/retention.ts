// AI evaluation data retention (Phase 4 — dark).
//
// Three clocks, one daily cron:
//  - transcripts cleared from eval docs after transcriptRetentionDays
//    (default 90) — the eval outlives its transcript, labelled in UI;
//  - whole eval docs DELETED after evalRetentionDays (default 730) —
//    child-derived judgments must not persist indefinitely (APP 11.2, the
//    period is stated in the privacy notice);
//  - classification-cache entries deleted after ~12 months.
//
// Transcript clearing uses a monotonic evaluatedAt cursor in
// aiEvalOpsConfig/retentionState so already-cleaned docs are never
// rescanned (Firestore cannot query on field absence).

import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {errorCodeForLog} from "../log_safety";
import {recordCronRun} from "../ops_heartbeat";
import {AiEvalOpsConfig, readAiEvalOpsConfig} from "./config";

export const RETENTION_STATE_DOC = "aiEvalOpsConfig/retentionState";
export const CLASSIFICATION_CACHE_RETENTION_DAYS = 365;
export const RETENTION_PAGE_SIZE = 300;
const DAY_MS = 86_400_000;

export interface RetentionResult {
  transcriptsCleared: number;
  evalsDeleted: number;
  classificationsDeleted: number;
}

// Clears expired transcripts, advancing the cursor. Never rescans.
export async function clearExpiredTranscripts(
  db: FirebaseFirestore.Firestore,
  cfg: AiEvalOpsConfig,
  now: Date
): Promise<number> {
  const cutoff = Timestamp.fromMillis(
    now.getTime() - cfg.transcriptRetentionDays * DAY_MS
  );
  const stateRef = db.doc(RETENTION_STATE_DOC);
  const stateSnap = await stateRef.get();
  const state = (stateSnap.data() ?? {}) as Record<string, unknown>;
  const cursor = state.transcriptCursorEvaluatedAt;

  let query = db.collectionGroup("comprehensionEvals")
    .where("evaluatedAt", "<", cutoff)
    .orderBy("evaluatedAt", "asc")
    .limit(RETENTION_PAGE_SIZE);
  if (cursor instanceof Timestamp) {
    query = db.collectionGroup("comprehensionEvals")
      .where("evaluatedAt", ">", cursor)
      .where("evaluatedAt", "<", cutoff)
      .orderBy("evaluatedAt", "asc")
      .limit(RETENTION_PAGE_SIZE);
  }
  const snap = await query.get();
  if (snap.docs.length === 0) return 0;

  let cleared = 0;
  const batch = db.batch();
  let lastEvaluatedAt: Timestamp | null = null;
  for (const doc of snap.docs) {
    const data = (doc.data() ?? {}) as Record<string, unknown>;
    if (data.evaluatedAt instanceof Timestamp) {
      lastEvaluatedAt = data.evaluatedAt;
    }
    if (typeof data.transcript === "string" && data.transcript.length > 0) {
      batch.update(doc.ref, {
        transcript: FieldValue.delete(),
        transcriptRemovedAt: FieldValue.serverTimestamp(),
      });
      cleared++;
    }
  }
  if (lastEvaluatedAt) {
    batch.set(stateRef, {
      transcriptCursorEvaluatedAt: lastEvaluatedAt,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  await batch.commit();
  return cleared;
}

// Deletes whole eval docs past the eval retention period.
export async function deleteExpiredEvals(
  db: FirebaseFirestore.Firestore,
  cfg: AiEvalOpsConfig,
  now: Date
): Promise<number> {
  const cutoff = Timestamp.fromMillis(
    now.getTime() - cfg.evalRetentionDays * DAY_MS
  );
  const snap = await db.collectionGroup("comprehensionEvals")
    .where("evaluatedAt", "<", cutoff)
    .orderBy("evaluatedAt", "asc")
    .limit(RETENTION_PAGE_SIZE)
    .get();
  if (snap.docs.length === 0) return 0;
  const batch = db.batch();
  for (const doc of snap.docs) {
    batch.delete(doc.ref);
  }
  await batch.commit();
  return snap.docs.length;
}

// Deletes stale classification-cache entries (~12-month TTL).
export async function deleteExpiredClassifications(
  db: FirebaseFirestore.Firestore,
  now: Date
): Promise<number> {
  const cutoff = new Date(
    now.getTime() - CLASSIFICATION_CACHE_RETENTION_DAYS * DAY_MS
  );
  const snap = await db.collection("aiQuestionClassifications")
    .where("classifiedAt", "<", cutoff)
    .orderBy("classifiedAt", "asc")
    .limit(RETENTION_PAGE_SIZE)
    .get();
  if (snap.docs.length === 0) return 0;
  const batch = db.batch();
  for (const doc of snap.docs) {
    batch.delete(doc.ref);
  }
  await batch.commit();
  return snap.docs.length;
}

export async function runAiEvalRetention(
  db: FirebaseFirestore.Firestore,
  cfg: AiEvalOpsConfig,
  now: Date
): Promise<RetentionResult> {
  const transcriptsCleared = await clearExpiredTranscripts(db, cfg, now);
  const evalsDeleted = await deleteExpiredEvals(db, cfg, now);
  const classificationsDeleted = await deleteExpiredClassifications(db, now);
  return {transcriptsCleared, evalsDeleted, classificationsDeleted};
}

// Daily, after the midnight sweep and before audio retention at 04:00.
export const aiEvalRetention = onSchedule(
  {
    schedule: "30 3 * * *",
    timeZone: "Australia/Sydney",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    try {
      const db = admin.firestore();
      const cfg = await readAiEvalOpsConfig();
      const result = await runAiEvalRetention(db, cfg, new Date());
      functions.logger.info("aiEval.retention.completed", {
        transcriptsCleared: result.transcriptsCleared,
        evalsDeleted: result.evalsDeleted,
        classificationsDeleted: result.classificationsDeleted,
      });
      await recordCronRun(
        "aiEvalRetention",
        "ok",
        `transcripts=${result.transcriptsCleared} ` +
        `evals=${result.evalsDeleted} ` +
        `classifications=${result.classificationsDeleted}`
      );
    } catch (err: unknown) {
      functions.logger.error("aiEval.retention.failed", {
        errorCode: errorCodeForLog(err),
      });
      await recordCronRun("aiEvalRetention", "error", errorCodeForLog(err));
    }
  }
);
