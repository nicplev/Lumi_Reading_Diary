// Scheduled cleanup for comprehension audio recordings.
//
// Reads /platformConfig/comprehensionRetention (written by the super-admin
// portal). When enabled, deletes Storage objects + clears the audio fields
// on reading-log docs older than `retentionDays`. The reading-log doc itself
// is preserved — only the audio is removed.
//
// Mirrors the scheduled-pubsub pattern used by impersonation.ts:849.

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

const RETENTION_DOC = "platformConfig/comprehensionRetention";
const BATCH_SIZE = 500;
const DAY_MS = 86_400_000;

// Bounds match those enforced server-side in @lumi/server-ops. The function
// re-validates so a hand-edited Firestore doc cannot deliver an absurd value.
const MIN_RETENTION_DAYS = 7;
const MAX_RETENTION_DAYS = 730;

interface RetentionConfig {
  enabled: boolean;
  retentionDays: number;
}

interface RunStats {
  deletedCount: number;
  failedCount: number;
  durationMs: number;
  cutoffISO: string;
  retentionDays: number;
}

interface SkippedReason {
  skipped: true;
  reason: string;
}

async function readRetentionConfig(
  db: FirebaseFirestore.Firestore
): Promise<RetentionConfig | null> {
  const snap = await db.doc(RETENTION_DOC).get();
  const data = snap.data();
  if (!snap.exists || !data) return null;
  const enabled = data.enabled === true;
  const retentionDays =
    typeof data.retentionDays === "number" ? data.retentionDays : 0;
  return {enabled, retentionDays};
}

// Deletes the Storage object at `path`, swallowing the 404 case so the loop
// stays idempotent across retried cron runs and replays.
async function deleteStorageObjectIfExists(path: string): Promise<void> {
  try {
    await admin.storage().bucket().file(path).delete();
  } catch (err: unknown) {
    const code = (err as {code?: number}).code;
    if (code === 404) return;
    throw err;
  }
}

async function performCleanup(
  performedBy: string,
  performedByEmail: string | null
): Promise<RunStats | SkippedReason> {
  const startedAtMs = Date.now();
  const db = admin.firestore();
  const config = await readRetentionConfig(db);

  if (!config) return {skipped: true, reason: "config_missing"} as const;
  if (!config.enabled) return {skipped: true, reason: "disabled"} as const;
  if (
    !Number.isInteger(config.retentionDays) ||
    config.retentionDays < MIN_RETENTION_DAYS ||
    config.retentionDays > MAX_RETENTION_DAYS
  ) {
    return {skipped: true, reason: "invalid_retentionDays"} as const;
  }

  const cutoff = admin.firestore.Timestamp.fromMillis(
    startedAtMs - config.retentionDays * DAY_MS
  );
  const cutoffISO = cutoff.toDate().toISOString();

  let deletedCount = 0;
  let failedCount = 0;
  // Defence-in-depth: the page loop cannot exceed (BATCH_SIZE × N) per run.
  // The collection-group query keeps returning expired docs until they get
  // patched (we clear comprehensionAudioUploaded), so without an outer cap
  // a failing batch could spin forever. 50 pages × 500 docs = 25k recordings,
  // far beyond any realistic 24-hour backlog.
  const MAX_PAGES = 50;

  for (let page = 0; page < MAX_PAGES; page++) {
    const snap = await db
      .collectionGroup("readingLogs")
      .where("comprehensionAudioUploaded", "==", true)
      .where("createdAt", "<", cutoff)
      .limit(BATCH_SIZE)
      .get();

    if (snap.empty) break;

    for (const doc of snap.docs) {
      const data = doc.data();
      const path = data.comprehensionAudioPath as string | undefined;
      try {
        if (path) await deleteStorageObjectIfExists(path);
        await doc.ref.update({
          comprehensionAudioPath: admin.firestore.FieldValue.delete(),
          comprehensionAudioDurationSec: admin.firestore.FieldValue.delete(),
          comprehensionAudioUploaded: false,
          comprehensionAudioDeletedAt:
            admin.firestore.FieldValue.serverTimestamp(),
        });
        deletedCount++;
      } catch (err) {
        failedCount++;
        functions.logger.error("comprehensionAudio.retention.deleteFailed", {
          logPath: doc.ref.path,
          storagePath: path,
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }

    if (snap.size < BATCH_SIZE) break;
  }

  const stats: RunStats = {
    deletedCount,
    failedCount,
    durationMs: Date.now() - startedAtMs,
    cutoffISO,
    retentionDays: config.retentionDays,
  };

  await db.doc(RETENTION_DOC).set(
    {
      lastRunAt: admin.firestore.FieldValue.serverTimestamp(),
      lastRunStats: stats,
    },
    {merge: true}
  );

  await db.collection("adminAuditLog").add({
    action: "comprehensionAudio.retentionRun",
    performedBy,
    performedByEmail: performedByEmail ?? undefined,
    targetType: "platformConfig",
    targetId: "comprehensionRetention",
    metadata: stats,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return stats;
}

export const cleanupComprehensionAudio = functions
  .runWith({timeoutSeconds: 540, memory: "512MB"})
  .pubsub.schedule("every 24 hours")
  .timeZone("Australia/Sydney")
  .onRun(async () => {
    const result = await performCleanup(
      "system:cleanupComprehensionAudio",
      null
    );
    if ("skipped" in result) {
      functions.logger.info("comprehensionAudio.retention.skipped", result);
    } else {
      functions.logger.info("comprehensionAudio.retention.completed", result);
    }
    return null;
  });

// ─────────────────────────────────────────────────────────────────────────────
// deleteComprehensionAudio: teacher / school-admin per-row trash button.
//
// The mobile app cannot delete Storage objects directly (storage.rules denies
// all client deletes). This callable verifies the caller is a teacher or
// schoolAdmin at the log's school, then performs the same delete the cron
// would perform on expiry.
// ─────────────────────────────────────────────────────────────────────────────

interface DeleteOneInput {
  schoolId?: unknown;
  logId?: unknown;
}

type CallerRole = "teacher" | "schoolAdmin";

async function resolveCallerRole(
  uid: string,
  schoolId: string
): Promise<CallerRole | null> {
  const userSnap = await admin
    .firestore()
    .collection("schools")
    .doc(schoolId)
    .collection("users")
    .doc(uid)
    .get();
  if (!userSnap.exists) return null;
  const role = userSnap.data()?.role;
  if (role === "teacher" || role === "schoolAdmin") return role;
  return null;
}

export const deleteComprehensionAudio = functions
  .runWith({timeoutSeconds: 30, memory: "256MB"})
  .https.onCall(async (data: DeleteOneInput, context) => {
    const uid = context.auth?.uid;
    if (!uid) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Sign in required"
      );
    }
    const schoolId =
      typeof data.schoolId === "string" ? data.schoolId.trim() : "";
    const logId = typeof data.logId === "string" ? data.logId.trim() : "";
    if (!schoolId || !logId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "schoolId and logId are required"
      );
    }

    const role = await resolveCallerRole(uid, schoolId);
    if (!role) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Only teachers or school admins of this school can delete recordings"
      );
    }

    const db = admin.firestore();
    const logRef = db
      .collection("schools")
      .doc(schoolId)
      .collection("readingLogs")
      .doc(logId);
    const snap = await logRef.get();
    if (!snap.exists) {
      throw new functions.https.HttpsError("not-found", "Reading log not found");
    }
    const logData = snap.data() ?? {};
    if (logData.comprehensionAudioUploaded !== true) {
      // Already cleared (by cron, bulk, or a concurrent click). Treat as a
      // no-op success so the UI's optimistic hide doesn't error.
      return {deleted: false, reason: "no_audio"};
    }
    const storagePath = logData.comprehensionAudioPath as string | undefined;
    if (storagePath) {
      await deleteStorageObjectIfExists(storagePath);
    }
    await logRef.update({
      comprehensionAudioPath: admin.firestore.FieldValue.delete(),
      comprehensionAudioDurationSec: admin.firestore.FieldValue.delete(),
      comprehensionAudioUploaded: false,
      comprehensionAudioDeletedAt:
        admin.firestore.FieldValue.serverTimestamp(),
    });

    const callerEmail = context.auth?.token?.email as string | undefined;
    await db.collection("adminAuditLog").add({
      action: "comprehensionAudio.manualDelete",
      performedBy: uid,
      performedByEmail: callerEmail ?? null,
      targetType: "readingLog",
      targetId: logId,
      schoolId,
      metadata: {
        source: role === "teacher" ? "manualTeacher" : "manualSchoolAdmin",
        storagePath: storagePath ?? null,
      },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {deleted: true};
  });
