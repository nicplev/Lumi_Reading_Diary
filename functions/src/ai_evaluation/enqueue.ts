// AI evaluation job enqueue (Phase 2 — ships dark).
//
// The ONLY entry point is enqueueAfterAudioConfirm, called after the
// canonical audio receipt transaction in confirmComprehensionAudioUpload
// has committed. Both gates fail closed, and the wrapper is log-only:
// recording confirmation must NEVER fail because of anything in here.
//
// Job doc: aiEvalJobs/{schoolId}_{logId} (deny-all in firestore.rules).
// A re-upload produces a newer comprehensionAudioUploadedAt on the log;
// enqueueing again transactionally resets the existing job to `queued`
// so the eval is re-run against the audio the teacher will actually hear.

import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {errorCodeForLog} from "../log_safety";
import {AUDIO_VALIDATION_VERSION} from "../audio_media_validation";
import {
  AI_EVALUATION_FLAG_DOC,
  platformAiEvaluationEnabled,
  schoolAiEvaluationEnabled,
} from "./gates";

// Deterministic job id — one job per (school, log) pair.
export function aiEvalJobId(schoolId: string, logId: string): string {
  return `${schoolId}_${logId}`;
}

export interface AiEvalJobSource {
  schoolId: string;
  logId: string;
  studentId: string;
  classId: string;
  sourceUploadedAt: Timestamp;
  audioObjectGeneration: string;
  audioValidationVersion: string;
}

// Builds the initial job document payload.
export function buildAiEvalJobData(
  source: AiEvalJobSource
): Record<string, unknown> {
  return {
    schoolId: source.schoolId,
    logId: source.logId,
    studentId: source.studentId,
    classId: source.classId,
    status: "queued",
    attempts: 0,
    createdAt: FieldValue.serverTimestamp(),
    sourceUploadedAt: source.sourceUploadedAt,
    audioObjectGeneration: source.audioObjectGeneration,
    audioValidationVersion: source.audioValidationVersion,
  };
}

// A pre-existing job is reset only when it points at an OLDER upload than
// the one just confirmed. Missing or malformed stamps count as older so a
// damaged job can always be recovered by re-uploading.
export function shouldResetExistingJob(
  existing: unknown,
  newSourceUploadedAt: Timestamp
): boolean {
  const record =
    existing && typeof existing === "object" ?
      (existing as Record<string, unknown>) :
      {};
  const prior = record.sourceUploadedAt;
  if (!(prior instanceof Timestamp)) return true;
  return prior.toMillis() < newSourceUploadedAt.toMillis();
}

// Error-code check tolerant of gRPC numeric and string style codes.
function isAlreadyExistsError(err: unknown): boolean {
  const code = (err as {code?: number | string}).code;
  return code === 6 || code === "already-exists" || code === "ALREADY_EXISTS";
}

export type EnqueueOutcome =
  | "queued"
  | "reset"
  | "skipped:platform_disabled"
  | "skipped:school_disabled"
  | "skipped:log_missing"
  | "skipped:invalid_receipt"
  | "skipped:invalid_log"
  | "skipped:existing_newer";

// Core enqueue flow. Exported with an injectable Firestore handle so unit
// tests can drive it with a stub; production callers use the wrapper below.
export async function enqueueAiEvalJobCore(
  db: FirebaseFirestore.Firestore,
  params: {schoolId: string, logId: string}
): Promise<EnqueueOutcome> {
  const {schoolId, logId} = params;

  const flagSnap = await db.doc(AI_EVALUATION_FLAG_DOC).get();
  if (!flagSnap.exists || !platformAiEvaluationEnabled(flagSnap.data())) {
    return "skipped:platform_disabled";
  }

  const schoolSnap = await db.doc(`schools/${schoolId}`).get();
  if (!schoolSnap.exists || !schoolAiEvaluationEnabled(schoolSnap.data())) {
    return "skipped:school_disabled";
  }

  const logSnap = await db.doc(`schools/${schoolId}/readingLogs/${logId}`).get();
  if (!logSnap.exists) return "skipped:log_missing";
  const log = (logSnap.data() ?? {}) as Record<string, unknown>;

  const uploadedAt = log.comprehensionAudioUploadedAt;
  const generation =
    typeof log.comprehensionAudioObjectGeneration === "string" ?
      log.comprehensionAudioObjectGeneration :
      "";
  if (
    log.comprehensionAudioUploaded !== true ||
    log.comprehensionAudioValidationVersion !== AUDIO_VALIDATION_VERSION ||
    !generation ||
    !(uploadedAt instanceof Timestamp)
  ) {
    // Only a current, fully validated canonical receipt may feed the AI
    // pipeline — never the untrusted pending namespace or a legacy stamp.
    return "skipped:invalid_receipt";
  }

  const studentId =
    typeof log.studentId === "string" ? log.studentId.trim() : "";
  const classId = typeof log.classId === "string" ? log.classId.trim() : "";
  if (!studentId || !classId) return "skipped:invalid_log";

  const source: AiEvalJobSource = {
    schoolId,
    logId,
    studentId,
    classId,
    sourceUploadedAt: uploadedAt,
    audioObjectGeneration: generation,
    audioValidationVersion: AUDIO_VALIDATION_VERSION,
  };
  const jobRef = db.doc(`aiEvalJobs/${aiEvalJobId(schoolId, logId)}`);

  try {
    await jobRef.create(buildAiEvalJobData(source));
    return "queued";
  } catch (err: unknown) {
    if (!isAlreadyExistsError(err)) throw err;
  }

  return db.runTransaction(async (transaction) => {
    const existing = await transaction.get(jobRef);
    if (!existing.exists) {
      transaction.create(jobRef, buildAiEvalJobData(source));
      return "queued";
    }
    if (!shouldResetExistingJob(existing.data(), source.sourceUploadedAt)) {
      return "skipped:existing_newer";
    }
    transaction.update(jobRef, {
      status: "queued",
      attempts: 0,
      sourceUploadedAt: source.sourceUploadedAt,
      audioObjectGeneration: source.audioObjectGeneration,
      audioValidationVersion: source.audioValidationVersion,
      requeuedAt: FieldValue.serverTimestamp(),
      claimedAt: FieldValue.delete(),
      completedAt: FieldValue.delete(),
      lastError: FieldValue.delete(),
      deferredReason: FieldValue.delete(),
    });
    return "reset";
  });
}

// Production entry point. Never throws: the audio confirmation result has
// already been committed and must not be affected by AI enqueue problems.
export async function enqueueAfterAudioConfirm(
  params: {schoolId: string, logId: string}
): Promise<void> {
  try {
    const outcome = await enqueueAiEvalJobCore(admin.firestore(), params);
    functions.logger.info("aiEval.enqueue.outcome", {outcome});
  } catch (err: unknown) {
    functions.logger.warn("aiEval.enqueue.failed", {
      errorCode: errorCodeForLog(err),
    });
  }
}
