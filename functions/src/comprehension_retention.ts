// Scheduled cleanup for comprehension audio recordings.
//
// Reads /platformConfig/comprehensionRetention (written by the super-admin
// portal). Cleanup is always active: it deletes Storage objects + clears the audio fields
// on reading-log docs older than `retentionDays`. The reading-log doc itself
// is preserved — only the audio is removed.
//
// Mirrors the scheduled-pubsub pattern used by impersonation.ts:849.

import * as functions from "firebase-functions/v1";
import {onCall, onRequest, HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {createHash} from "node:crypto";
import {GoogleAuth, IdTokenClient} from "google-auth-library";
import {assertNotReadOnly} from "./read_only_guard";
import {recordCronRun} from "./ops_heartbeat";
import {errorCodeForLog} from "./log_safety";
import {
  retentionDecisionForSchool,
  schoolAudioCollectionIsAuthorised,
  schoolAudioPlaybackIsEnabled,
} from "./audio_authority";
import {
  AUDIO_VALIDATION_VERSION,
  AudioMediaValidationError,
  MAX_TRANSCODED_AUDIO_BYTES,
  MAX_UNTRUSTED_AUDIO_BYTES,
  validateAndTranscodeAudioBuffer,
  type ValidatedAudioBuffer,
} from "./audio_media_validation";
import {classComprehensionQuestion} from "./ai_evaluation/question";
import {enqueueAfterAudioConfirm} from "./ai_evaluation/enqueue";

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

const AUDIO_CONFIRM_CALLABLE_OPTIONS = {
  timeoutSeconds: 60,
  memory: "512MiB" as const,
  maxInstances: 10,
  concurrency: 10,
  enforceAppCheck: COMPREHENSION_AUDIO_APP_CHECK_ENFORCED,
  consumeAppCheckToken: COMPREHENSION_AUDIO_APP_CHECK_ENFORCED,
};

type AudioAppCheckRequest = {
  app?: {alreadyConsumed?: boolean};
};

/**
 * Reject replayed limited-use App Check tokens while enforcement is live.
 * @param {AudioAppCheckRequest} request Callable request attestation state.
 * @param {boolean} enforcementEnabled Active rollout state; injectable in tests.
 */
export function assertFreshAudioAppCheckToken(
  request: AudioAppCheckRequest,
  enforcementEnabled = COMPREHENSION_AUDIO_APP_CHECK_ENFORCED
): void {
  if (
    enforcementEnabled &&
    request.app?.alreadyConsumed === true
  ) {
    throw new HttpsError(
      "failed-precondition",
      "The App Check token has already been used"
    );
  }
}

const AUDIO_VALIDATOR_FUNCTION_NAME = "validateComprehensionAudioMedia";
const AUDIO_VALIDATOR_REGION = "australia-southeast1";
const AUDIO_VALIDATOR_SERVICE_ACCOUNT =
  "lumi-audio-validator@lumi-ninc-au.iam.gserviceaccount.com";
const AUDIO_VALIDATOR_CALLER =
  "lumi-functions-runtime@lumi-ninc-au.iam.gserviceaccount.com";
const AUDIO_RATE_LIMIT_WINDOW_MS = 15 * 60 * 1000;
const AUDIO_RATE_LIMIT_MAX_ATTEMPTS = 20;
const PENDING_AUDIO_MAX_AGE_MS = 24 * 60 * 60 * 1000;
const PENDING_AUDIO_MAX_PER_RUN = 5000;

// Bounds match those enforced server-side in @lumi/server-ops. The function
// re-validates so a hand-edited Firestore doc cannot deliver an absurd value.
const MIN_RETENTION_DAYS = 30;
const MAX_RETENTION_DAYS = 730;
const DEFAULT_RETENTION_DAYS = 90;

interface RetentionConfig {
  retentionDays: number;
}

interface RunStats {
  deletedCount: number;
  failedCount: number;
  durationMs: number;
  schoolCount: number;
  legacyDefaultRetentionDays: number;
  retentionPolicyCounts: Record<string, number>;
  fallbackSchoolCount: number;
  legacySevenDaySchoolCount: number;
  trigger: "cron" | "manual";
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
 * Private holding path for client-uploaded, untrusted media. Clients never
 * write the canonical playback path; only validated server output lands there.
 * @param {string} schoolId Owning school document ID.
 * @param {string} logId Owning reading-log document ID.
 * @return {string} Canonical pending-upload Storage object path.
 */
export function comprehensionAudioUploadObjectPath(
  schoolId: string,
  logId: string
): string {
  return `comprehension_audio_uploads/${schoolId}/${logId}.m4a`;
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
): Promise<RetentionConfig> {
  const snap = await db.doc(RETENTION_DOC).get();
  const data = snap.data();
  const raw = data?.retentionDays;
  const retentionDays = typeof raw === "number" &&
    Number.isInteger(raw) &&
    raw >= MIN_RETENTION_DAYS &&
    raw <= MAX_RETENTION_DAYS ? raw : DEFAULT_RETENTION_DAYS;
  return {retentionDays};
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
    const code = (err as {code?: number | string}).code;
    if (code === 404 || code === "404") return;
    throw err;
  }
}

// Delete only the generation that was inspected. A parent may retry-overwrite
// a pending upload while confirmation is running; a rejected old generation
// must never cause the backend to delete a newer attempt.
async function deleteStorageObjectGenerationIfExists(
  path: string,
  generation: string
): Promise<void> {
  try {
    await admin.storage().bucket().file(path, {generation}).delete();
  } catch (err: unknown) {
    const code = (err as {code?: number | string}).code;
    if (code === 404 || code === "404" || code === 412 || code === "412") {
      return;
    }
    throw err;
  }
}

async function performCleanup(
  performedBy: string,
  performedByEmail: string | null
): Promise<RunStats> {
  const startedAtMs = Date.now();
  const db = admin.firestore();
  const config = await readRetentionConfig(db);

  let deletedCount = 0;
  let failedCount = 0;
  let fallbackSchoolCount = 0;
  let legacySevenDaySchoolCount = 0;
  const retentionPolicyCounts: Record<string, number> = {};
  // Defence-in-depth: the page loop cannot exceed (BATCH_SIZE × N) per run.
  // The collection-group query keeps returning expired docs until they get
  // patched (we clear comprehensionAudioUploaded), so without an outer cap
  // a failing batch could spin forever. 50 pages × 500 docs = 25k recordings,
  // far beyond any realistic 24-hour backlog.
  const MAX_PAGES = 50;

  const schools = await db.collection("schools").get();
  for (const school of schools.docs) {
    const retentionDecision = retentionDecisionForSchool(
      school.data(),
      config.retentionDays
    );
    const retentionDays = retentionDecision.days;
    if (retentionDecision.source === "fallback") fallbackSchoolCount++;
    if (retentionDecision.source === "legacySchool") {
      legacySevenDaySchoolCount++;
    }
    retentionPolicyCounts[String(retentionDays)] =
      (retentionPolicyCounts[String(retentionDays)] ?? 0) + 1;
    const cutoff = Timestamp.fromMillis(
      startedAtMs - retentionDays * DAY_MS
    );

    for (let page = 0; page < MAX_PAGES; page++) {
      const snap = await school.ref
        .collection("readingLogs")
        .where("comprehensionAudioUploaded", "==", true)
        .where("createdAt", "<", cutoff)
        .limit(BATCH_SIZE)
        .get();

      if (snap.empty) break;

      for (const doc of snap.docs) {
        const data = doc.data();
        const schoolId = schoolIdForReadingLogRef(doc.ref);
        const expectedPath = schoolId === school.id ?
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
          if (
            !schoolId ||
            !expectedPath ||
            audioPathMustBeQuarantined(storedPath, expectedPath)
          ) {
            if (schoolId && expectedPath) {
              await deleteStorageObjectIfExists(expectedPath);
              await deleteStorageObjectIfExists(
                comprehensionAudioUploadObjectPath(schoolId, doc.id)
              );
            }
            await doc.ref.update({
              comprehensionAudioPath: FieldValue.delete(),
              comprehensionAudioDurationSec: FieldValue.delete(),
              comprehensionAudioUploaded: false,
              comprehensionAudioUploadedAt: FieldValue.delete(),
              comprehensionAudioObjectGeneration: FieldValue.delete(),
              comprehensionAudioReviewStatus: FieldValue.delete(),
              comprehensionAudioReviewedAt: FieldValue.delete(),
              comprehensionAudioReviewedGeneration: FieldValue.delete(),
              comprehensionAudioSourceGeneration: FieldValue.delete(),
              comprehensionAudioValidationVersion: FieldValue.delete(),
              comprehensionAudioValidatedDurationMs: FieldValue.delete(),
              comprehensionAudioSha256: FieldValue.delete(),
              comprehensionAudioPathRejectedAt:
                FieldValue.serverTimestamp(),
            });
            failedCount++;
            functions.logger.error("comprehensionAudio.retention.pathRejected");
            continue;
          }

          await deleteStorageObjectIfExists(expectedPath);
          await deleteStorageObjectIfExists(
            comprehensionAudioUploadObjectPath(schoolId, doc.id)
          );
          await doc.ref.update({
            comprehensionAudioPath: FieldValue.delete(),
            comprehensionAudioDurationSec: FieldValue.delete(),
            comprehensionAudioUploaded: false,
            comprehensionAudioUploadedAt: FieldValue.delete(),
            comprehensionAudioObjectGeneration: FieldValue.delete(),
            comprehensionAudioReviewStatus: FieldValue.delete(),
            comprehensionAudioReviewedAt: FieldValue.delete(),
            comprehensionAudioReviewedGeneration: FieldValue.delete(),
            comprehensionAudioSourceGeneration: FieldValue.delete(),
            comprehensionAudioValidationVersion: FieldValue.delete(),
            comprehensionAudioValidatedDurationMs: FieldValue.delete(),
            comprehensionAudioSha256: FieldValue.delete(),
            comprehensionAudioDeletedAt:
              FieldValue.serverTimestamp(),
          });
          deletedCount++;
        } catch (err) {
          failedCount++;
          functions.logger.error("comprehensionAudio.retention.deleteFailed", {
            errorCode: errorCodeForLog(err),
          });
        }
      }

      if (snap.size < BATCH_SIZE) break;
    }
  }

  const stats: RunStats = {
    deletedCount,
    failedCount,
    durationMs: Date.now() - startedAtMs,
    schoolCount: schools.size,
    legacyDefaultRetentionDays: config.retentionDays,
    retentionPolicyCounts,
    fallbackSchoolCount,
    legacySevenDaySchoolCount,
    trigger: "cron",
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
    // Fixed slot (was floating "every 24 hours") so the AI-eval sweep's
    // midnight run precedes retention; the >=7-day retention floor remains
    // the real guarantee for deferred jobs.
    schedule: "0 4 * * *",
    timeZone: "Australia/Sydney",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const result = await performCleanup(
      "system:cleanupComprehensionAudio",
      null
    );
    functions.logger.info("comprehensionAudio.retention.completed", result);
    await recordCronRun("cleanupComprehensionAudio", "ok");
    return;
  });

// Unconfirmed uploads can be stranded if the app is killed after Storage
// succeeds but before the receipt callable runs. They contain a child's voice,
// so a separate fail-safe removes pending objects after 24 hours even when the
// the school's normal retention window has not elapsed.
export const cleanupPendingComprehensionAudio = onSchedule(
  {
    schedule: "every 24 hours",
    timeZone: "Australia/Sydney",
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async () => {
    const cutoffMs = Date.now() - PENDING_AUDIO_MAX_AGE_MS;
    const [files] = await admin.storage().bucket().getFiles({
      prefix: "comprehension_audio_uploads/",
      maxResults: PENDING_AUDIO_MAX_PER_RUN,
      autoPaginate: false,
    });
    let deletedCount = 0;
    let skippedCount = 0;
    let failedCount = 0;
    for (const file of files) {
      try {
        let metadata = file.metadata;
        if (!metadata?.timeCreated || !metadata?.generation) {
          [metadata] = await file.getMetadata();
        }
        const createdMs = Date.parse(String(metadata.timeCreated ?? ""));
        const generation = String(metadata.generation ?? "");
        if (!Number.isFinite(createdMs) || !generation || createdMs >= cutoffMs) {
          skippedCount++;
          continue;
        }
        await deleteStorageObjectGenerationIfExists(file.name, generation);
        deletedCount++;
      } catch (err: unknown) {
        failedCount++;
        functions.logger.error("comprehensionAudio.pendingCleanup.failed", {
          errorCode: errorCodeForLog(err),
        });
      }
    }
    const result = {deletedCount, skippedCount, failedCount, scanned: files.length};
    functions.logger.info("comprehensionAudio.pendingCleanup.completed", result);
    await recordCronRun(
      "cleanupPendingComprehensionAudio",
      failedCount > 0 ? "error" : "ok",
      failedCount > 0 ? `${failedCount} delete failures` : undefined
    );
  }
);

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

interface AudioValidatorResponse {
  validationVersion: string;
  durationMs: number;
  sizeBytes: number;
  sha256: string;
  audioBase64: string;
}

let validatorClientPromise: Promise<IdTokenClient> | null = null;

function audioValidatorUrl(): string {
  const override = process.env.COMPREHENSION_AUDIO_VALIDATOR_URL?.trim();
  if (override) return override;
  const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
  if (!projectId) throw new Error("Cannot resolve validator project id");
  return `https://${AUDIO_VALIDATOR_REGION}-${projectId}.cloudfunctions.net/` +
    AUDIO_VALIDATOR_FUNCTION_NAME;
}

function parseValidatorResponse(data: unknown): ValidatedAudioBuffer {
  if (!data || typeof data !== "object") {
    throw new Error("Audio validator returned no result");
  }
  const result = data as Partial<AudioValidatorResponse>;
  if (
    result.validationVersion !== AUDIO_VALIDATION_VERSION ||
    !Number.isInteger(result.durationMs) ||
    (result.durationMs as number) < 500 ||
    (result.durationMs as number) > 60_750 ||
    !Number.isInteger(result.sizeBytes) ||
    (result.sizeBytes as number) <= 0 ||
    (result.sizeBytes as number) >= MAX_TRANSCODED_AUDIO_BYTES ||
    typeof result.sha256 !== "string" ||
    !/^[a-f0-9]{64}$/.test(result.sha256) ||
    typeof result.audioBase64 !== "string" ||
    result.audioBase64.length > Math.ceil(MAX_TRANSCODED_AUDIO_BYTES / 3) * 4
  ) {
    throw new Error("Audio validator returned an invalid result");
  }
  const bytes = Buffer.from(result.audioBase64, "base64");
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  if (
    bytes.length !== result.sizeBytes ||
    sha256 !== result.sha256 ||
    !hasIsoMediaFtypSignature(bytes.subarray(0, 32))
  ) {
    throw new Error("Audio validator result integrity check failed");
  }
  return {
    bytes,
    durationMs: result.durationMs as number,
    sizeBytes: result.sizeBytes as number,
    sha256,
  };
}

async function processAudioInIsolatedValidator(
  bytes: Buffer
): Promise<ValidatedAudioBuffer> {
  // Emulator tests run the exact decoder locally. Production crosses an IAM-
  // authenticated process boundary into a no-data-permissions worker, keeping
  // native media parsing out of the privileged Firestore/Storage container.
  if (
    process.env.FUNCTIONS_EMULATOR === "true" ||
    Boolean(process.env.FIRESTORE_EMULATOR_HOST)
  ) {
    return validateAndTranscodeAudioBuffer(bytes);
  }
  const url = audioValidatorUrl();
  validatorClientPromise ??= new GoogleAuth().getIdTokenClient(url);
  const client = await validatorClientPromise;
  try {
    const response = await client.request<AudioValidatorResponse>({
      url,
      method: "POST",
      headers: {"content-type": "application/json"},
      data: {audioBase64: bytes.toString("base64")},
      timeout: 25_000,
    });
    return parseValidatorResponse(response.data);
  } catch (err: unknown) {
    const status = (err as {response?: {status?: number}}).response?.status;
    if (status === 422) {
      throw new AudioMediaValidationError("Media decode rejected the upload");
    }
    throw err;
  }
}

async function consumeAudioValidationRateLimit(uid: string): Promise<void> {
  const key = createHash("sha256").update(uid).digest("hex");
  const ref = admin.firestore().doc(`backendRateLimits/audioValidation_${key}`);
  const nowMs = Date.now();
  await admin.firestore().runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    const data = snap.data() ?? {};
    const windowStartMs = data.windowStart?.toMillis?.() ?? 0;
    const inCurrentWindow =
      windowStartMs > 0 && nowMs - windowStartMs < AUDIO_RATE_LIMIT_WINDOW_MS;
    const attempts = inCurrentWindow && Number.isInteger(data.attempts) ?
      data.attempts :
      0;
    if (attempts >= AUDIO_RATE_LIMIT_MAX_ATTEMPTS) {
      throw new HttpsError(
        "resource-exhausted",
        "Too many recording validation attempts. Please try again later."
      );
    }
    transaction.set(ref, {
      windowStart: Timestamp.fromMillis(inCurrentWindow ? windowStartMs : nowMs),
      attempts: attempts + 1,
      updatedAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(nowMs + AUDIO_RATE_LIMIT_WINDOW_MS * 2),
    });
  });
}

/**
 * Native decoder/transcoder worker. IAM permits only the pinned Functions
 * runtime service account to invoke it, while this worker's own service
 * account has no Firestore or Storage roles. It receives bytes and returns
 * bytes; it never receives a school, child, log, bucket or user identifier.
 */
export const validateComprehensionAudioMedia = onRequest(
  {
    timeoutSeconds: 30,
    memory: "512MiB",
    maxInstances: 5,
    concurrency: 1,
    serviceAccount: AUDIO_VALIDATOR_SERVICE_ACCOUNT,
    invoker: [AUDIO_VALIDATOR_CALLER],
  },
  async (request, response) => {
    if (request.method !== "POST") {
      response.status(405).json({error: "method_not_allowed"});
      return;
    }
    const encoded = request.body?.audioBase64;
    const maxBase64Length = Math.ceil(MAX_UNTRUSTED_AUDIO_BYTES / 3) * 4;
    if (
      typeof encoded !== "string" ||
      encoded.length === 0 ||
      encoded.length > maxBase64Length ||
      !/^[A-Za-z0-9+/]*={0,2}$/.test(encoded)
    ) {
      response.status(422).json({error: "invalid_media"});
      return;
    }
    const bytes = Buffer.from(encoded, "base64");
    if (bytes.toString("base64") !== encoded) {
      response.status(422).json({error: "invalid_media"});
      return;
    }
    try {
      const result = await validateAndTranscodeAudioBuffer(bytes);
      response.status(200).json({
        validationVersion: AUDIO_VALIDATION_VERSION,
        durationMs: result.durationMs,
        sizeBytes: result.sizeBytes,
        sha256: result.sha256,
        audioBase64: result.bytes.toString("base64"),
      } satisfies AudioValidatorResponse);
    } catch (err: unknown) {
      if (err instanceof AudioMediaValidationError) {
        functions.logger.warn("comprehensionAudio.validator.rejected", {
          errorCode: errorCodeForLog(err),
          inputBytes: bytes.length,
        });
        response.status(422).json({error: "invalid_media"});
        return;
      }
      functions.logger.error("comprehensionAudio.validator.failed", {
        errorCode: errorCodeForLog(err),
      });
      response.status(500).json({error: "validation_unavailable"});
    }
  }
);

/**
 * Server-owned receipt for a client Storage upload. The caller can upload only
 * to an untrusted pending object enforced by Storage rules; this callable
 * validates and transcodes it before publishing a server-owned canonical
 * object and setting the audio fields with Admin SDK privileges.
 */
export const confirmComprehensionAudioUpload = onCall(
  AUDIO_CONFIRM_CALLABLE_OPTIONS,
  async (request) => {
    const data: ConfirmUploadInput = request.data;
    assertFreshAudioAppCheckToken(request);
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
    const [flagSnap, schoolSnap, logSnap] = await Promise.all([
      db.doc(RECORDING_FLAG_DOC).get(),
      db.doc(`schools/${schoolId}`).get(),
      db.doc(`schools/${schoolId}/readingLogs/${logId}`).get(),
    ]);
    if (
      !flagSnap.exists ||
      flagSnap.data()?.enabled !== true ||
      !schoolSnap.exists ||
      !schoolAudioCollectionIsAuthorised(schoolSnap.data())
    ) {
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
    if (
      logData.comprehensionAudioUploaded === true &&
      logData.comprehensionAudioPath === storagePath &&
      logData.comprehensionAudioValidationVersion === AUDIO_VALIDATION_VERSION
    ) {
      return {confirmed: true, alreadyConfirmed: true};
    }

    const uploadPath = comprehensionAudioUploadObjectPath(schoolId, logId);
    const bucket = admin.storage().bucket();
    const uploadFile = bucket.file(uploadPath);
    let metadata;
    try {
      [metadata] = await uploadFile.getMetadata();
    } catch (err: unknown) {
      const code = (err as {code?: number}).code;
      if (code === 404) {
        throw new HttpsError("not-found", "Recording upload not found");
      }
      throw err;
    }

    const size = Number(metadata.size ?? 0);
    const sourceGeneration = String(metadata.generation ?? "");
    const custom = metadata.metadata ?? {};
    if (
      !Number.isFinite(size) ||
      size <= 0 ||
      size >= MAX_UNTRUSTED_AUDIO_BYTES ||
      !sourceGeneration ||
      metadata.contentType !== "audio/mp4" ||
      custom.ownerUid !== uid ||
      custom.schoolId !== schoolId ||
      custom.logId !== logId ||
      custom.studentId !== logData.studentId
    ) {
      // Do not leave a rejected child recording sitting in the bucket.
      if (sourceGeneration) {
        await deleteStorageObjectGenerationIfExists(
          uploadPath,
          sourceGeneration
        );
      }
      throw new HttpsError(
        "failed-precondition",
        "Recording metadata failed validation"
      );
    }

    const versionedUpload = bucket.file(uploadPath, {
      generation: sourceGeneration,
    });
    let untrustedBytes: Buffer;
    try {
      [untrustedBytes] = await versionedUpload.download();
    } catch (err: unknown) {
      functions.logger.error("Audio pending upload read failed", {
        errorCode: errorCodeForLog(err),
      });
      throw new HttpsError("internal", "Could not validate recording upload");
    }
    if (
      untrustedBytes.length !== size ||
      !hasIsoMediaFtypSignature(untrustedBytes.subarray(0, 32))
    ) {
      await deleteStorageObjectGenerationIfExists(uploadPath, sourceGeneration);
      throw new HttpsError(
        "failed-precondition",
        "Recording content failed media validation"
      );
    }

    await consumeAudioValidationRateLimit(uid);

    let validated: ValidatedAudioBuffer;
    try {
      validated = await processAudioInIsolatedValidator(untrustedBytes);
    } catch (err: unknown) {
      if (err instanceof AudioMediaValidationError) {
        await deleteStorageObjectGenerationIfExists(uploadPath, sourceGeneration);
        throw new HttpsError(
          "failed-precondition",
          "Recording content failed media validation"
        );
      }
      functions.logger.error("Comprehension audio validator unavailable", {
        errorCode: errorCodeForLog(err),
      });
      // Preserve the pending upload for the offline queue to retry later.
      throw new HttpsError("internal", "Could not validate recording upload");
    }

    const canonicalFile = bucket.file(storagePath);
    let canonicalMetadata;
    try {
      // Create-only publication prevents two confirmations from overwriting
      // each other's validated object before either Firestore receipt commits.
      await canonicalFile.save(validated.bytes, {
        resumable: false,
        validation: "crc32c",
        preconditionOpts: {ifGenerationMatch: 0},
        metadata: {
          contentType: "audio/mp4",
          cacheControl: "private, no-store",
          metadata: {
            ownerUid: uid,
            schoolId,
            logId,
            studentId: String(logData.studentId),
            durationMs: String(validated.durationMs),
            sourceGeneration,
            validationVersion: AUDIO_VALIDATION_VERSION,
            sha256: validated.sha256,
          },
        },
      });
      [canonicalMetadata] = await canonicalFile.getMetadata();
    } catch (err: unknown) {
      const code = (err as {code?: number | string}).code;
      if (code !== 412 && code !== "412") throw err;

      // A previous attempt can crash after writing bytes but before stamping
      // Firestore. Reuse that orphan only when every server-derived identity
      // and integrity field matches this exact validation result.
      const [existing] = await canonicalFile.getMetadata();
      const existingCustom = existing.metadata ?? {};
      if (
        existing.contentType !== "audio/mp4" ||
        existingCustom.ownerUid !== uid ||
        existingCustom.schoolId !== schoolId ||
        existingCustom.logId !== logId ||
        existingCustom.studentId !== String(logData.studentId) ||
        existingCustom.durationMs !== String(validated.durationMs) ||
        existingCustom.sourceGeneration !== sourceGeneration ||
        existingCustom.validationVersion !== AUDIO_VALIDATION_VERSION ||
        existingCustom.sha256 !== validated.sha256
      ) {
        throw new HttpsError(
          "aborted",
          "Another recording confirmation is in progress. Please retry."
        );
      }
      canonicalMetadata = existing;
    }
    const canonicalGeneration = String(canonicalMetadata.generation ?? "");
    if (!canonicalGeneration) {
      await deleteStorageObjectIfExists(storagePath);
      throw new HttpsError("internal", "Could not finalize recording upload");
    }

    const validatedDurationSec = Math.max(
      1,
      Math.min(60, Math.round(validated.durationMs / 1000))
    );

    // Snapshot the class comprehension question onto the log so a later AI
    // evaluation scores against the question the child actually answered,
    // even if the teacher edits the class question afterwards. Best-effort:
    // an unreadable class doc falls back to the default question.
    const questionClassId =
      typeof logData.classId === "string" ? logData.classId.trim() : "";
    let comprehensionQuestionText = classComprehensionQuestion(undefined);
    if (questionClassId) {
      try {
        const classSnap = await db
          .doc(`schools/${schoolId}/classes/${questionClassId}`)
          .get();
        comprehensionQuestionText = classComprehensionQuestion(
          classSnap.data()
        );
      } catch (err: unknown) {
        functions.logger.warn(
          "Comprehension question read failed; using default",
          {errorCode: errorCodeForLog(err)}
        );
      }
    }

    try {
      await db.runTransaction(async (transaction) => {
        const [freshFlag, freshSchool, freshLog] = await Promise.all([
          transaction.get(db.doc(RECORDING_FLAG_DOC)),
          transaction.get(db.doc(`schools/${schoolId}`)),
          transaction.get(logSnap.ref),
        ]);
        if (
          !freshFlag.exists ||
          freshFlag.data()?.enabled !== true ||
          !freshSchool.exists ||
          !schoolAudioCollectionIsAuthorised(freshSchool.data())
        ) {
          throw new HttpsError(
            "failed-precondition",
            "Comprehension recording is not enabled"
          );
        }
        const freshData = freshLog.data() ?? {};
        if (!freshLog.exists) {
          throw new HttpsError("not-found", "Reading log not found");
        }
        if (
          freshData.parentId !== uid ||
          freshData.loggedByRole === "teacher" ||
          freshData.studentId !== logData.studentId
        ) {
          throw new HttpsError(
            "permission-denied",
            "Recording ownership changed during validation"
          );
        }
        transaction.update(logSnap.ref, {
          comprehensionAudioPath: storagePath,
          comprehensionAudioDurationSec: validatedDurationSec,
          comprehensionAudioUploaded: true,
          comprehensionAudioUploadedAt: FieldValue.serverTimestamp(),
          comprehensionAudioObjectGeneration: canonicalGeneration,
          // Review state belongs to this exact object generation and is shared
          // by the class teaching team. Every successful replacement starts a
          // fresh to-review item.
          comprehensionAudioReviewStatus: "pending",
          comprehensionAudioReviewedAt: FieldValue.delete(),
          comprehensionAudioReviewedGeneration: FieldValue.delete(),
          comprehensionAudioSourceGeneration: sourceGeneration,
          comprehensionAudioValidationVersion: AUDIO_VALIDATION_VERSION,
          comprehensionAudioValidatedDurationMs: validated.durationMs,
          comprehensionAudioSha256: validated.sha256,
          comprehensionQuestionText,
          comprehensionQuestionCapturedAt: FieldValue.serverTimestamp(),
        });
      });
    } catch (err: unknown) {
      await deleteStorageObjectGenerationIfExists(
        storagePath,
        canonicalGeneration
      );
      if (err instanceof HttpsError) {
        await deleteStorageObjectGenerationIfExists(
          uploadPath,
          sourceGeneration
        );
        throw err;
      }
      throw err;
    }

    try {
      await deleteStorageObjectGenerationIfExists(uploadPath, sourceGeneration);
    } catch (err: unknown) {
      // The validated canonical object and Firestore receipt are complete.
      // A scheduled pending-upload cleanup is the safe retry path for this
      // non-fatal residue rather than telling the client the save failed.
      functions.logger.warn("Comprehension audio pending cleanup failed", {
        errorCode: errorCodeForLog(err),
      });
    }

    // AI evaluation enqueue (dark until platform + school gates open).
    // Never throws — confirmation is already committed.
    await enqueueAfterAudioConfirm({schoolId, logId});

    return {
      confirmed: true,
      durationSec: validatedDurationSec,
      validationVersion: AUDIO_VALIDATION_VERSION,
    };
  }
);

export const deleteComprehensionAudio = onCall(
  AUDIO_CALLABLE_OPTIONS,
  async (request) => {
    const data: DeleteOneInput = request.data;
    assertFreshAudioAppCheckToken(request);
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
    await deleteStorageObjectIfExists(
      comprehensionAudioUploadObjectPath(schoolId, logId)
    );
    await logRef.update({
      comprehensionAudioPath: FieldValue.delete(),
      comprehensionAudioDurationSec: FieldValue.delete(),
      comprehensionAudioUploaded: false,
      comprehensionAudioUploadedAt: FieldValue.delete(),
      comprehensionAudioObjectGeneration: FieldValue.delete(),
      comprehensionAudioReviewStatus: FieldValue.delete(),
      comprehensionAudioReviewedAt: FieldValue.delete(),
      comprehensionAudioReviewedGeneration: FieldValue.delete(),
      comprehensionAudioSourceGeneration: FieldValue.delete(),
      comprehensionAudioValidationVersion: FieldValue.delete(),
      comprehensionAudioValidatedDurationMs: FieldValue.delete(),
      comprehensionAudioSha256: FieldValue.delete(),
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
    assertFreshAudioAppCheckToken(request);
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

    const db = admin.firestore();
    const [schoolSnap, snap] = await Promise.all([
      db.doc(`schools/${schoolId}`).get(),
      db.doc(`schools/${schoolId}/readingLogs/${logId}`).get(),
    ]);
    if (!schoolSnap.exists ||
        !schoolAudioPlaybackIsEnabled(schoolSnap.data())) {
      throw new HttpsError(
        "failed-precondition",
        "Recording playback is turned off for this school"
      );
    }
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
      // `not-found`, not `failed-precondition`: a missing recording is a
      // distinct client state (hide the player) from policy/validation failures
      // (which stay `failed-precondition` and show a message). The client keys on
      // this code to tell "deleted" apart from "temporarily unavailable".
      throw new HttpsError(
        "not-found",
        "This log has no recording."
      );
    }
    const objectGeneration =
      typeof logData.comprehensionAudioObjectGeneration === "string" ?
        logData.comprehensionAudioObjectGeneration.trim() :
        "";
    if (
      logData.comprehensionAudioValidationVersion !== AUDIO_VALIDATION_VERSION ||
      !objectGeneration
    ) {
      throw new HttpsError(
        "failed-precondition",
        "This recording has not completed server media validation."
      );
    }
    const storagePath = comprehensionAudioObjectPath(schoolId, logId);

    const expiresAt = Date.now() + AUDIO_URL_TTL_MS;
    try {
      const [url] = await admin
        .storage()
        .bucket()
        .file(storagePath, {generation: objectGeneration})
        .getSignedUrl({action: "read", expires: expiresAt});
      return {url, expiresInSec: Math.floor(AUDIO_URL_TTL_MS / 1000)};
    } catch (err) {
      functions.logger.error("getComprehensionAudioUrl sign failed", {
        errorCode: errorCodeForLog(err),
      });
      throw new HttpsError(
        "internal",
        "Could not prepare the recording for playback."
      );
    }
  });
