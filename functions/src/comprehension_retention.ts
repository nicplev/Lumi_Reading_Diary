// Scheduled cleanup for comprehension audio recordings.
//
// Reads /platformConfig/comprehensionRetention (written by the super-admin
// portal). When enabled, deletes Storage objects + clears the audio fields
// on reading-log docs older than `retentionDays`. The reading-log doc itself
// is preserved — only the audio is removed.
//
// Mirrors the scheduled-pubsub pattern used by impersonation.ts:849.

import * as functions from "firebase-functions/v1";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {assertNotReadOnly} from "./read_only_guard";
import {recordCronRun} from "./ops_heartbeat";

const RETENTION_DOC = "platformConfig/comprehensionRetention";
const RECORDING_FLAG_DOC = "platformConfig/comprehensionRecording";
const BATCH_SIZE = 500;
const DAY_MS = 86_400_000;
const COMPREHENSION_AUDIO_APP_CHECK_ENFORCED =
  process.env.COMPREHENSION_AUDIO_APP_CHECK_ENFORCED === "true";

const AUDIO_CALLABLE_OPTIONS = {
  timeoutSeconds: 30,
  memory: "256MiB" as const,
  enforceAppCheck: COMPREHENSION_AUDIO_APP_CHECK_ENFORCED,
  consumeAppCheckToken: COMPREHENSION_AUDIO_APP_CHECK_ENFORCED,
};

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

/**
 * The only valid object path for a reading log's comprehension recording.
 * Privileged code must derive this path from trusted Firestore path segments;
 * it must never use the client-editable value stored on the log document.
 * @param {string} schoolId Owning school document ID.
 * @param {string} logId Owning reading-log document ID.
 * @return {string} Canonical Storage object path.
 */
export function comprehensionAudioObjectPath(
  schoolId: string,
  logId: string
): string {
  return `schools/${schoolId}/comprehension_audio/${logId}.m4a`;
}

/**
 * Legacy rows are safe for automatic cleanup only when their stored metadata
 * exactly agrees with the path derived from the Firestore document path.
 * @param {unknown} storedPath Untrusted value stored on the log document.
 * @param {string} expectedPath Server-derived canonical object path.
 * @return {boolean} True when the row must be quarantined, not followed.
 */
export function audioPathMustBeQuarantined(
  storedPath: unknown,
  expectedPath: string
): boolean {
  return typeof storedPath !== "string" || storedPath !== expectedPath;
}

/**
 * Minimal content sniff for the ISO Base Media File Format used by m4a/mp4.
 * Client-supplied MIME metadata is not evidence of the uploaded bytes.
 * @param {Buffer} bytes First bytes of the uploaded object.
 * @return {boolean} Whether the first box has a plausible `ftyp` signature.
 */
export function hasIsoMediaFtypSignature(bytes: Buffer): boolean {
  if (bytes.length < 12 || bytes.toString("ascii", 4, 8) !== "ftyp") {
    return false;
  }
  return bytes.readUInt32BE(0) >= 8;
}

/**
 * Resolve the school id for a direct schools/{schoolId}/readingLogs/{logId}
 * document. Collection-group queries can also find a collection named
 * readingLogs elsewhere, so cleanup fails closed unless the full shape is the
 * canonical Lumi path.
 * @param {FirebaseFirestore.DocumentReference} ref Reading-log reference.
 * @return {string | null} School id for a canonical log path, otherwise null.
 */
function schoolIdForReadingLogRef(
  ref: FirebaseFirestore.DocumentReference
): string | null {
  const schoolRef = ref.parent.parent;
  if (!schoolRef || schoolRef.parent.id !== "schools") return null;
  return schoolRef.id;
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

async function assertComprehensionRecordingEnabled(
  db: FirebaseFirestore.Firestore
): Promise<void> {
  const snap = await db.doc(RECORDING_FLAG_DOC).get();
  if (!snap.exists || snap.data()?.enabled !== true) {
    throw new HttpsError(
      "failed-precondition",
      "Comprehension recording is not enabled"
    );
  }
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

  const cutoff = Timestamp.fromMillis(
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
      const schoolId = schoolIdForReadingLogRef(doc.ref);
      const expectedPath = schoolId ?
        comprehensionAudioObjectPath(schoolId, doc.id) :
        null;
      const storedPath =
        typeof data.comprehensionAudioPath === "string" ?
          data.comprehensionAudioPath :
          null;
      try {
        // Never follow an unexpected client-supplied path with Admin SDK
        // credentials. Quarantine the row so it cannot repeatedly enter this
        // cleanup query or be played, while retaining enough metadata for an
        // operator to investigate the legacy/corrupt value.
        if (!expectedPath || audioPathMustBeQuarantined(storedPath, expectedPath)) {
          await doc.ref.update({
            comprehensionAudioPath: FieldValue.delete(),
            comprehensionAudioDurationSec: FieldValue.delete(),
            comprehensionAudioUploaded: false,
            comprehensionAudioPathRejectedAt:
              FieldValue.serverTimestamp(),
          });
          failedCount++;
          functions.logger.error("comprehensionAudio.retention.pathRejected", {
            logPath: doc.ref.path,
            storedPath,
            expectedPath,
          });
          continue;
        }

        await deleteStorageObjectIfExists(expectedPath);
        await doc.ref.update({
          comprehensionAudioPath: FieldValue.delete(),
          comprehensionAudioDurationSec: FieldValue.delete(),
          comprehensionAudioUploaded: false,
          comprehensionAudioDeletedAt:
            FieldValue.serverTimestamp(),
        });
        deletedCount++;
      } catch (err) {
        failedCount++;
        functions.logger.error("comprehensionAudio.retention.deleteFailed", {
          logPath: doc.ref.path,
          storagePath: expectedPath,
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
      lastRunAt: FieldValue.serverTimestamp(),
      lastRunStats: stats,
    },
    {merge: true}
  );

  await db.collection("adminAuditLog").add({
    action: "comprehensionAudio.retentionRun",
    performedBy,
    performedByEmail: performedByEmail ?? null,
    targetType: "platformConfig",
    targetId: "comprehensionRetention",
    metadata: stats,
    createdAt: FieldValue.serverTimestamp(),
  });

  return stats;
}

export const cleanupComprehensionAudio = onSchedule(
  {
    schedule: "every 24 hours",
    timeZone: "Australia/Sydney",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const result = await performCleanup(
      "system:cleanupComprehensionAudio",
      null
    );
    if ("skipped" in result) {
      functions.logger.info("comprehensionAudio.retention.skipped", result);
      await recordCronRun("cleanupComprehensionAudio", "skipped", result.reason);
    } else {
      functions.logger.info("comprehensionAudio.retention.completed", result);
      await recordCronRun("cleanupComprehensionAudio", "ok");
    }
    return;
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

interface ConfirmUploadInput {
  schoolId?: unknown;
  logId?: unknown;
  durationSec?: unknown;
}

type CallerRole = "teacher" | "schoolAdmin";

/**
 * Evaluate a teacher assignment using the same class fields as Firestore
 * rules. Exported for regression tests around audio access decisions.
 * @param {string} uid Teacher uid.
 * @param {FirebaseFirestore.DocumentData} classData Class document data.
 * @return {boolean} Whether the teacher owns or co-teaches the class.
 */
export function teacherIsAssignedToClassData(
  uid: string,
  classData: FirebaseFirestore.DocumentData
): boolean {
  const teacherIds = Array.isArray(classData.teacherIds) ?
    classData.teacherIds :
    [];
  return classData.teacherId === uid || teacherIds.includes(uid);
}

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

/**
 * School admins have school-wide access. A teacher must be assigned to the
 * reading log's class; same-school role membership alone is not sufficient.
 * @param {string} uid Authenticated caller uid.
 * @param {string} schoolId Owning school id.
 * @param {CallerRole} role Resolved server-side membership role.
 * @param {FirebaseFirestore.DocumentData} logData Reading-log data.
 * @return {Promise<boolean>} Whether the caller may access this log's audio.
 */
async function callerCanAccessLogAudio(
  uid: string,
  schoolId: string,
  role: CallerRole,
  logData: FirebaseFirestore.DocumentData
): Promise<boolean> {
  if (role === "schoolAdmin") return true;
  const classId =
    typeof logData.classId === "string" ? logData.classId.trim() : "";
  if (!classId) return false;
  const classSnap = await admin
    .firestore()
    .doc(`schools/${schoolId}/classes/${classId}`)
    .get();
  if (!classSnap.exists) return false;
  const classData = classSnap.data() ?? {};
  return teacherIsAssignedToClassData(uid, classData);
}

/**
 * Server-owned receipt for a client Storage upload. The caller can upload only
 * to the canonical object enforced by Storage rules; this callable verifies
 * the object again before setting the audio fields with Admin SDK privileges.
 */
export const confirmComprehensionAudioUpload = onCall(
  AUDIO_CALLABLE_OPTIONS,
  async (request) => {
    const data: ConfirmUploadInput = request.data;
    assertNotReadOnly(request);
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

    const schoolId =
      typeof data.schoolId === "string" ? data.schoolId.trim() : "";
    const logId = typeof data.logId === "string" ? data.logId.trim() : "";
    const durationSec = data.durationSec;
    if (
      !schoolId ||
      !logId ||
      !Number.isInteger(durationSec) ||
      (durationSec as number) < 1 ||
      (durationSec as number) > 60
    ) {
      throw new HttpsError(
        "invalid-argument",
        "schoolId, logId and a duration from 1 to 60 seconds are required"
      );
    }

    const db = admin.firestore();
    const [flagSnap, logSnap] = await Promise.all([
      db.doc(RECORDING_FLAG_DOC).get(),
      db.doc(`schools/${schoolId}/readingLogs/${logId}`).get(),
    ]);
    if (!flagSnap.exists || flagSnap.data()?.enabled !== true) {
      throw new HttpsError(
        "failed-precondition",
        "Comprehension recording is not enabled"
      );
    }
    if (!logSnap.exists) {
      throw new HttpsError("not-found", "Reading log not found");
    }
    const logData = logSnap.data() ?? {};
    if (logData.parentId !== uid || logData.loggedByRole === "teacher") {
      throw new HttpsError(
        "permission-denied",
        "Only the parent who created this log can attach its recording"
      );
    }

    const storagePath = comprehensionAudioObjectPath(schoolId, logId);
    const file = admin.storage().bucket().file(storagePath);
    let metadata;
    try {
      [metadata] = await file.getMetadata();
    } catch (err: unknown) {
      const code = (err as {code?: number}).code;
      if (code === 404) {
        throw new HttpsError("not-found", "Recording upload not found");
      }
      throw err;
    }

    const size = Number(metadata.size ?? 0);
    const custom = metadata.metadata ?? {};
    if (
      !Number.isFinite(size) ||
      size <= 0 ||
      size >= 2 * 1024 * 1024 ||
      metadata.contentType !== "audio/mp4" ||
      custom.ownerUid !== uid ||
      custom.schoolId !== schoolId ||
      custom.logId !== logId
    ) {
      // Do not leave a rejected child recording sitting in the bucket.
      await deleteStorageObjectIfExists(storagePath);
      throw new HttpsError(
        "failed-precondition",
        "Recording metadata failed validation"
      );
    }

    let header: Buffer;
    try {
      [header] = await file.download({start: 0, end: 31});
    } catch (err: unknown) {
      functions.logger.error("Audio signature read failed", {
        schoolId,
        logId,
        error: err instanceof Error ? err.message : String(err),
      });
      throw new HttpsError("internal", "Could not validate recording upload");
    }
    if (!hasIsoMediaFtypSignature(header)) {
      await deleteStorageObjectIfExists(storagePath);
      throw new HttpsError(
        "failed-precondition",
        "Recording content failed media validation"
      );
    }

    await logSnap.ref.update({
      comprehensionAudioPath: storagePath,
      comprehensionAudioDurationSec: durationSec,
      comprehensionAudioUploaded: true,
      comprehensionAudioUploadedAt:
        FieldValue.serverTimestamp(),
    });
    return {confirmed: true};
  }
);

export const deleteComprehensionAudio = onCall(
  AUDIO_CALLABLE_OPTIONS,
  async (request) => {
    const data: DeleteOneInput = request.data;
    assertNotReadOnly(request);
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError(
        "unauthenticated",
        "Sign in required"
      );
    }
    const schoolId =
      typeof data.schoolId === "string" ? data.schoolId.trim() : "";
    const logId = typeof data.logId === "string" ? data.logId.trim() : "";
    if (!schoolId || !logId) {
      throw new HttpsError(
        "invalid-argument",
        "schoolId and logId are required"
      );
    }

    const role = await resolveCallerRole(uid, schoolId);
    if (!role) {
      throw new HttpsError(
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
      throw new HttpsError("not-found", "Reading log not found");
    }
    const logData = snap.data() ?? {};
    if (!(await callerCanAccessLogAudio(uid, schoolId, role, logData))) {
      throw new HttpsError(
        "permission-denied",
        "You are not assigned to this reading log's class"
      );
    }
    if (logData.comprehensionAudioUploaded !== true) {
      // Already cleared (by cron, bulk, or a concurrent click). Treat as a
      // no-op success so the UI's optimistic hide doesn't error.
      return {deleted: false, reason: "no_audio"};
    }
    const storagePath = comprehensionAudioObjectPath(schoolId, logId);
    await deleteStorageObjectIfExists(storagePath);
    await logRef.update({
      comprehensionAudioPath: FieldValue.delete(),
      comprehensionAudioDurationSec: FieldValue.delete(),
      comprehensionAudioUploaded: false,
      comprehensionAudioDeletedAt:
        FieldValue.serverTimestamp(),
    });

    const callerEmail = request.auth?.token?.email as string | undefined;
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
      createdAt: FieldValue.serverTimestamp(),
    });

    return {deleted: true};
  });

// ─────────────────────────────────────────────────────────────────────────────
// getComprehensionAudioUrl: mint a short-lived signed URL for playback.
//
// The comprehension recording is a child's voice — PII at rest. The Storage
// object is NOT client-readable (storage.rules denies read on
// comprehension_audio); this callable is the sole read path. It verifies the
// caller is a teacher / school admin at the LOG'S school (playback is a
// teacher-only surface — the per-log audio player lives in the teacher comments
// sheet), then returns a 15-minute read-only signed URL. No enumeration: the
// caller must already know a real schoolId + logId, and the authz check binds
// the file to a log they can see.
//
// NOTE (deploy prerequisite): getSignedUrl requires the functions runtime
// service account to be able to sign blobs — grant it
// roles/iam.serviceAccountTokenCreator (or the iam.serviceAccounts.signBlob
// permission) if signing fails with an IAM error. Verify on-device before
// tightening the storage rule.
// ─────────────────────────────────────────────────────────────────────────────

interface AudioUrlInput {
  schoolId?: unknown;
  logId?: unknown;
}

const AUDIO_URL_TTL_MS = 15 * 60 * 1000;

export const getComprehensionAudioUrl = onCall(
  AUDIO_CALLABLE_OPTIONS,
  async (request) => {
    const data: AudioUrlInput = request.data;
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError(
        "unauthenticated",
        "Sign in required"
      );
    }
    const schoolId =
      typeof data.schoolId === "string" ? data.schoolId.trim() : "";
    const logId = typeof data.logId === "string" ? data.logId.trim() : "";
    if (!schoolId || !logId) {
      throw new HttpsError(
        "invalid-argument",
        "schoolId and logId are required"
      );
    }

    const role = await resolveCallerRole(uid, schoolId);
    if (!role) {
      throw new HttpsError(
        "permission-denied",
        "Only teachers or school admins of this school can play recordings"
      );
    }

    // The platform kill switch must block playback as well as new uploads.
    // Deletion intentionally remains available while disabled so schools can
    // remove already-collected recordings.
    await assertComprehensionRecordingEnabled(admin.firestore());

    const snap = await admin
      .firestore()
      .collection("schools")
      .doc(schoolId)
      .collection("readingLogs")
      .doc(logId)
      .get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "Reading log not found");
    }
    const logData = snap.data() ?? {};
    if (!(await callerCanAccessLogAudio(uid, schoolId, role, logData))) {
      throw new HttpsError(
        "permission-denied",
        "You are not assigned to this reading log's class"
      );
    }
    if (logData.comprehensionAudioUploaded !== true) {
      throw new HttpsError(
        "failed-precondition",
        "This log has no recording."
      );
    }
    const storagePath = comprehensionAudioObjectPath(schoolId, logId);

    const expiresAt = Date.now() + AUDIO_URL_TTL_MS;
    try {
      const [url] = await admin
        .storage()
        .bucket()
        .file(storagePath)
        .getSignedUrl({action: "read", expires: expiresAt});
      return {url, expiresInSec: Math.floor(AUDIO_URL_TTL_MS / 1000)};
    } catch (err) {
      functions.logger.error("getComprehensionAudioUrl sign failed", {
        uid,
        schoolId,
        logId,
        error: err instanceof Error ? err.message : String(err),
      });
      throw new HttpsError(
        "internal",
        "Could not prepare the recording for playback."
      );
    }
  });
