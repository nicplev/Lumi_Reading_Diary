// AI evaluation pipeline worker + sweep (Phase 3 — ships dark).
//
// processAiEvalJob fires on job creation; sweepAiEvalJobs is the ONLY
// re-dispatch mechanism (flipping a job back to `queued` does not re-fire
// onDocumentCreated) and the only recovery for lost trigger events under
// retry:false. All provider work is dependency-injected so unit tests
// drive the full state machine without emulators or providers.

import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {errorCodeForLog} from "../log_safety";
import {recordCronRun} from "../ops_heartbeat";
import {AUDIO_VALIDATION_VERSION} from "../audio_media_validation";
import {
  AI_EVALUATION_FLAG_DOC,
  platformAiEvaluationEnabled,
  schoolAiEvaluationEnabled,
} from "./gates";
import {
  AiEvalOpsConfig,
  estimateEvalCostUsd,
  isAllowlistedModel,
  readAiEvalOpsConfig,
  STT_PRICE_PER_BILLED_SEC_USD,
} from "./config";
import {
  reserveGlobalDailyEvalBudget,
  reserveSchoolDailyEvalBudget,
  schoolCapFromAdminMeta,
} from "./budget";
import {
  incrementDailyMetrics,
  readDailyMetrics,
  recordSchoolMonthlyUsage,
} from "./metrics";
import {
  AudioUnavailableError,
  LOW_STT_CONFIDENCE_THRESHOLD,
  STT_LANGUAGE,
  SttQuotaError,
  TRANSCRIPTION_PROVIDER,
  TranscriptionResult,
  transcribeCanonicalAudio,
} from "./transcription";
import {classifyQuestion, QuestionClassification} from "./classification";
import {
  EvaluationRequest,
  ProviderOutcome,
  redactStudentName,
  runEvaluation,
} from "./evaluation";
import {rubricForKey, RUBRIC_VERSION} from "./rubrics";
import {computeSortKey, validateEvalResponse} from "./schemas";
import {clampComprehensionQuestion, classComprehensionQuestion, DEFAULT_COMPREHENSION_QUESTION} from "./question";

export type JobTerminal =
  | "done"
  | "disabled"
  | "log_deleted"
  | "deferred:school_cap"
  | "deferred:global_cap"
  | "deferred:stt_quota"
  | "deferred:provider_quota"
  | "deferred:config_invalid"
  | "failed"
  | "poisoned"
  | "not_claimed";

export interface WorkerDeps {
  db: FirebaseFirestore.Firestore;
  readOpsConfig: () => Promise<AiEvalOpsConfig>;
  transcribe: (params: {
    schoolId: string, logId: string, objectGeneration: string,
  }) => Promise<TranscriptionResult>;
  classify: (
    db: FirebaseFirestore.Firestore,
    params: {question: string, model: string, promptVersion: number},
  ) => Promise<QuestionClassification>;
  evaluate: (request: EvaluationRequest) => Promise<ProviderOutcome>;
  now: () => Date;
}

export function defaultWorkerDeps(): WorkerDeps {
  return {
    db: admin.firestore(),
    readOpsConfig: readAiEvalOpsConfig,
    transcribe: transcribeCanonicalAudio,
    classify: classifyQuestion,
    evaluate: runEvaluation,
    now: () => new Date(),
  };
}

const CLAIMABLE_ON_CREATE: readonly string[] = ["queued"];
const CLAIMABLE_ON_SWEEP: readonly string[] = ["queued", "failed", "deferred"];

class RetryableWorkerError extends Error {}

interface ClaimedJob {
  schoolId: string;
  logId: string;
  studentId: string;
  classId: string;
  attempts: number;
  sourceUploadedAt: Timestamp | null;
}

// Transactionally claims a job (status -> processing, attempts++).
async function claimJob(
  db: FirebaseFirestore.Firestore,
  jobId: string,
  claimableStates: readonly string[],
  stuckCutoffMs: number | null,
  now: Date
): Promise<ClaimedJob | null> {
  const jobRef = db.doc(`aiEvalJobs/${jobId}`);
  return db.runTransaction(async (transaction) => {
    const snap = await transaction.get(jobRef);
    if (!snap.exists) return null;
    const data = (snap.data() ?? {}) as Record<string, unknown>;
    const status = typeof data.status === "string" ? data.status : "";
    let claimable = claimableStates.includes(status);
    if (!claimable && status === "processing" && stuckCutoffMs !== null) {
      const claimedAt = data.claimedAt;
      claimable =
        claimedAt instanceof Timestamp &&
        now.getTime() - claimedAt.toMillis() > stuckCutoffMs;
    }
    if (!claimable) return null;
    transaction.update(jobRef, {
      status: "processing",
      claimedAt: FieldValue.serverTimestamp(),
      attempts: FieldValue.increment(1),
      deferredReason: FieldValue.delete(),
    });
    return {
      schoolId: typeof data.schoolId === "string" ? data.schoolId : "",
      logId: typeof data.logId === "string" ? data.logId : "",
      studentId: typeof data.studentId === "string" ? data.studentId : "",
      classId: typeof data.classId === "string" ? data.classId : "",
      attempts: Number(data.attempts ?? 0) + 1,
      sourceUploadedAt:
        data.sourceUploadedAt instanceof Timestamp ?
          data.sourceUploadedAt :
          null,
    };
  });
}

// Completes the job, guarding against a mid-flight re-upload reset: if the
// job's sourceUploadedAt moved past what we processed, leave it queued for
// the sweep to re-run against the newer audio.
async function completeJob(
  db: FirebaseFirestore.Firestore,
  jobId: string,
  processedSourceUploadedAt: Timestamp | null,
  update: Record<string, unknown>
): Promise<void> {
  const jobRef = db.doc(`aiEvalJobs/${jobId}`);
  await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(jobRef);
    if (!snap.exists) return;
    const data = (snap.data() ?? {}) as Record<string, unknown>;
    const current = data.sourceUploadedAt;
    if (
      processedSourceUploadedAt &&
      current instanceof Timestamp &&
      current.toMillis() > processedSourceUploadedAt.toMillis()
    ) {
      // A newer upload was enqueued mid-flight; keep the job queued.
      transaction.update(jobRef, {status: "queued"});
      return;
    }
    transaction.update(jobRef, update as FirebaseFirestore.DocumentData);
  });
}

function terminalUpdate(
  terminal: JobTerminal,
  extra?: Record<string, unknown>
): Record<string, unknown> {
  if (terminal.startsWith("deferred:")) {
    return {
      status: "deferred",
      deferredReason: terminal.slice("deferred:".length),
      completedAt: FieldValue.serverTimestamp(),
      ...extra,
    };
  }
  if (terminal === "disabled" || terminal === "log_deleted") {
    return {
      status: "done",
      doneReason: terminal,
      completedAt: FieldValue.serverTimestamp(),
      ...extra,
    };
  }
  return {
    status: terminal === "done" ? "done" : terminal,
    completedAt: FieldValue.serverTimestamp(),
    ...extra,
  };
}

interface EvalDocBase {
  schoolId: string;
  logId: string;
  studentId: string;
  classId: string;
  logDate: Timestamp | null;
  audioUploadedAt: Timestamp | null;
}

function evalDocRef(
  db: FirebaseFirestore.Firestore,
  schoolId: string,
  logId: string
): FirebaseFirestore.DocumentReference {
  return db.doc(`schools/${schoolId}/comprehensionEvals/${logId}`);
}

// Writes a non-scored eval doc (skip / flagged-without-LLM states) so the
// teacher surface shows a definitive state instead of eternal pending.
function unscoredEvalDoc(
  base: EvalDocBase,
  cfg: AiEvalOpsConfig,
  status: "skipped" | "flagged" | "failed",
  flags: string[]
): Record<string, unknown> {
  return {
    schoolId: base.schoolId,
    logId: base.logId,
    studentId: base.studentId,
    classId: base.classId,
    logDate: base.logDate,
    status,
    audioUploadedAt: base.audioUploadedAt,
    transcriptChars: 0,
    sttConfidence: null,
    languageCode: STT_LANGUAGE,
    transcriptionProvider: TRANSCRIPTION_PROVIDER,
    questionTextUsed: null,
    questionSource: null,
    questionCategories: [],
    rubricKey: null,
    rubricVersion: RUBRIC_VERSION,
    summary: null,
    criterionScores: [],
    overallLevel: null,
    sortKey: 0,
    confidence: null,
    flags,
    assessable: false,
    model: cfg.model,
    promptVersion: cfg.promptVersion,
    usage: null,
    evaluatedAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
  };
}

// Full pipeline for one claimed job. Returns the terminal state reached.
export async function processAiEvalJobCore(
  deps: WorkerDeps,
  jobId: string,
  options?: {sweep?: boolean}
): Promise<JobTerminal> {
  const {db} = deps;
  const cfg = await deps.readOpsConfig();
  const now = deps.now();
  const claim = await claimJob(
    db,
    jobId,
    options?.sweep ? CLAIMABLE_ON_SWEEP : CLAIMABLE_ON_CREATE,
    options?.sweep ? cfg.evalTimeoutSec * 1000 * 2 + 300_000 : null,
    now
  );
  if (!claim) return "not_claimed";

  const finish = (
    terminal: JobTerminal,
    extra?: Record<string, unknown>
  ): Promise<JobTerminal> =>
    completeJob(
      db, jobId, claim.sourceUploadedAt, terminalUpdate(terminal, extra)
    ).then(() => terminal);

  try {
    // Re-check gates at claim: the kill switch or entitlement may have
    // flipped while the job sat queued. Off => done without spend.
    const [flagSnap, schoolSnap] = await Promise.all([
      db.doc(AI_EVALUATION_FLAG_DOC).get(),
      db.doc(`schools/${claim.schoolId}`).get(),
    ]);
    if (
      !flagSnap.exists ||
      !platformAiEvaluationEnabled(flagSnap.data()) ||
      !schoolSnap.exists ||
      !schoolAiEvaluationEnabled(schoolSnap.data())
    ) {
      return await finish("disabled");
    }

    if (!isAllowlistedModel(cfg.model)) {
      // A config model without AU-regional probe evidence must never run;
      // defer + error signal instead of silently routing elsewhere.
      functions.logger.error("aiEval.worker.modelNotAllowlisted");
      return await finish("deferred:config_invalid");
    }

    const logRef = db.doc(
      `schools/${claim.schoolId}/readingLogs/${claim.logId}`
    );
    const logSnap = await logRef.get();
    if (!logSnap.exists) return await finish("log_deleted");
    const log = (logSnap.data() ?? {}) as Record<string, unknown>;

    const base: EvalDocBase = {
      schoolId: claim.schoolId,
      logId: claim.logId,
      studentId: claim.studentId,
      classId: claim.classId,
      logDate: log.date instanceof Timestamp ? log.date : null,
      audioUploadedAt:
        log.comprehensionAudioUploadedAt instanceof Timestamp ?
          log.comprehensionAudioUploadedAt :
          null,
    };

    const generation =
      typeof log.comprehensionAudioObjectGeneration === "string" ?
        log.comprehensionAudioObjectGeneration :
        "";
    if (
      log.comprehensionAudioUploaded !== true ||
      log.comprehensionAudioValidationVersion !== AUDIO_VALIDATION_VERSION ||
      !generation
    ) {
      await evalDocRef(db, claim.schoolId, claim.logId).set(
        unscoredEvalDoc(base, cfg, "skipped", ["audio_unavailable"])
      );
      return await finish("done");
    }

    const durationSec = Number(log.comprehensionAudioDurationSec ?? 0);
    if (durationSec < cfg.minDurationSec) {
      await evalDocRef(db, claim.schoolId, claim.logId).set(
        unscoredEvalDoc(base, cfg, "flagged", ["too_short"])
      );
      await incrementDailyMetrics(db, {flagged: 1}, now);
      return await finish("done");
    }

    // Budget: per-school reservation first, then the sharded global cap.
    const adminMetaSnap = await db
      .doc(`schools/${claim.schoolId}/adminMeta/aiEvaluation`)
      .get();
    const cap = schoolCapFromAdminMeta(
      adminMetaSnap.exists ? adminMetaSnap.data() : undefined,
      cfg.defaultDailyCapPerSchool
    );
    if (!(await reserveSchoolDailyEvalBudget(db, claim.schoolId, cap, now))) {
      await incrementDailyMetrics(db, {deferred: 1}, now);
      return await finish("deferred:school_cap");
    }
    if (!(await reserveGlobalDailyEvalBudget(db, cfg.globalDailyCap, now))) {
      await incrementDailyMetrics(db, {deferred: 1}, now);
      return await finish("deferred:global_cap");
    }

    // Transcribe the canonical object at its exact recorded generation.
    let transcription: TranscriptionResult;
    try {
      transcription = await deps.transcribe({
        schoolId: claim.schoolId,
        logId: claim.logId,
        objectGeneration: generation,
      });
    } catch (err: unknown) {
      if (err instanceof SttQuotaError) {
        functions.logger.error("aiEval.worker.sttQuota");
        await incrementDailyMetrics(db, {deferred: 1}, now);
        return await finish("deferred:stt_quota");
      }
      if (err instanceof AudioUnavailableError) {
        await evalDocRef(db, claim.schoolId, claim.logId).set(
          unscoredEvalDoc(base, cfg, "skipped", ["audio_unavailable"])
        );
        return await finish("done");
      }
      throw new RetryableWorkerError(errorCodeForLog(err));
    }

    const sttMetric = {sttSeconds: transcription.billedSec};
    if (!transcription.transcript.trim()) {
      await evalDocRef(db, claim.schoolId, claim.logId).set(
        unscoredEvalDoc(base, cfg, "flagged", ["inaudible"])
      );
      await incrementDailyMetrics(db, {flagged: 1, ...sttMetric}, now);
      await recordSchoolMonthlyUsage(
        db, claim.schoolId, {sttSeconds: transcription.billedSec}, now
      );
      return await finish("done");
    }

    const workerFlags: string[] = [];
    if (transcription.confidence < LOW_STT_CONFIDENCE_THRESHOLD) {
      workerFlags.push("low_stt_confidence");
    }
    let transcript = transcription.transcript;
    if (transcript.length > cfg.maxTranscriptChars) {
      transcript = transcript.slice(0, cfg.maxTranscriptChars);
    }

    // Question: log snapshot -> current class question -> default.
    let questionText: string;
    let questionSource: "log" | "classCurrent" | "default";
    if (
      typeof log.comprehensionQuestionText === "string" &&
      log.comprehensionQuestionText.trim()
    ) {
      questionText = clampComprehensionQuestion(log.comprehensionQuestionText);
      questionSource = "log";
    } else {
      const classSnap = await db
        .doc(`schools/${claim.schoolId}/classes/${claim.classId}`)
        .get();
      const classQuestion = classSnap.exists ?
        classComprehensionQuestion(classSnap.data()) :
        DEFAULT_COMPREHENSION_QUESTION;
      questionText = classQuestion;
      questionSource = classQuestion === DEFAULT_COMPREHENSION_QUESTION ?
        "default" :
        "classCurrent";
    }

    const classification = await deps.classify(db, {
      question: questionText,
      model: cfg.model,
      promptVersion: cfg.promptVersion,
    });
    const rubric = rubricForKey(classification.rubricKey);

    // Redact the student's registered name(s) before anything leaves the
    // process boundary.
    const studentSnap = await db
      .doc(`schools/${claim.schoolId}/students/${claim.studentId}`)
      .get();
    const studentName =
      typeof studentSnap.data()?.name === "string" ?
        (studentSnap.data()?.name as string) :
        "";
    const redacted = redactStudentName(transcript, [studentName]);

    const outcome = await deps.evaluate({
      model: cfg.model,
      rubric,
      promptVersion: cfg.promptVersion,
      questionText,
      transcript: redacted,
      timeoutSec: cfg.evalTimeoutSec,
    });

    if (outcome.kind === "quota") {
      functions.logger.error("aiEval.worker.providerQuota");
      await incrementDailyMetrics(db, {deferred: 1, ...sttMetric}, now);
      return await finish("deferred:provider_quota");
    }
    if (outcome.kind === "safety_blocked") {
      await evalDocRef(db, claim.schoolId, claim.logId).set({
        ...unscoredEvalDoc(base, cfg, "flagged",
          [...workerFlags, "concerning_content"]),
        transcriptChars: transcript.length,
        questionTextUsed: questionText,
        questionSource,
        questionCategories: classification.categories,
        rubricKey: rubric.key,
      });
      await incrementDailyMetrics(
        db, {flagged: 1, safetyBlocks: 1, llmCalls: 1, ...sttMetric}, now
      );
      return await finish("done");
    }
    if (outcome.kind === "recitation") {
      await evalDocRef(db, claim.schoolId, claim.logId).set({
        ...unscoredEvalDoc(base, cfg, "flagged",
          [...workerFlags, "recitation_blocked"]),
        transcriptChars: transcript.length,
        questionTextUsed: questionText,
        questionSource,
        questionCategories: classification.categories,
        rubricKey: rubric.key,
      });
      await incrementDailyMetrics(
        db, {flagged: 1, llmCalls: 1, ...sttMetric}, now
      );
      return await finish("done");
    }
    if (outcome.kind === "retryable") {
      throw new RetryableWorkerError(outcome.reason);
    }

    const validation = validateEvalResponse(outcome.parsed, rubric);
    if (!validation.ok) {
      throw new RetryableWorkerError(`invalid_response:${validation.reason}`);
    }
    const value = validation.value;
    const flags = [...workerFlags, ...value.flags];
    const costUsd =
      estimateEvalCostUsd(cfg.model, outcome.usage) +
      transcription.billedSec * STT_PRICE_PER_BILLED_SEC_USD;

    await evalDocRef(db, claim.schoolId, claim.logId).set({
      schoolId: claim.schoolId,
      logId: claim.logId,
      studentId: claim.studentId,
      classId: claim.classId,
      logDate: base.logDate,
      status: value.assessable && flags.length === 0 ? "complete" : "flagged",
      audioUploadedAt: base.audioUploadedAt,
      transcript,
      transcriptChars: transcript.length,
      sttConfidence: transcription.confidence,
      languageCode: STT_LANGUAGE,
      transcriptionProvider: TRANSCRIPTION_PROVIDER,
      questionTextUsed: questionText,
      questionSource,
      questionCategories: classification.categories,
      rubricKey: rubric.key,
      rubricVersion: RUBRIC_VERSION,
      summary: value.summary,
      criterionScores: value.criterionScores,
      overallLevel: value.overallLevel,
      sortKey: computeSortKey(value),
      confidence: value.confidence,
      flags,
      assessable: value.assessable,
      model: cfg.model,
      promptVersion: cfg.promptVersion,
      usage: outcome.usage,
      evaluatedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    });

    await incrementDailyMetrics(db, {
      evaluated: 1,
      flagged: flags.length > 0 ? 1 : 0,
      llmCalls: 1,
      classificationCalls: classification.usedLlmCall ? 1 : 0,
      inputTokens: outcome.usage.inputTokens,
      outputTokens: outcome.usage.outputTokens,
      thoughtsTokens: outcome.usage.thoughtsTokens,
      cachedTokens: outcome.usage.cachedTokens,
      estCostUsdMillis: Math.round(costUsd * 1000),
      ...sttMetric,
    }, now);
    await recordSchoolMonthlyUsage(db, claim.schoolId, {
      evaluated: 1,
      sttSeconds: transcription.billedSec,
      inputTokens: outcome.usage.inputTokens,
      outputTokens: outcome.usage.outputTokens,
      thoughtsTokens: outcome.usage.thoughtsTokens,
      cachedTokens: outcome.usage.cachedTokens,
      classificationCalls: classification.usedLlmCall ? 1 : 0,
      estCostUsdMillis: Math.round(costUsd * 1000),
    }, now);

    return await finish("done");
  } catch (err: unknown) {
    const reason =
      err instanceof RetryableWorkerError ?
        err.message :
        errorCodeForLog(err);
    if (claim.attempts >= cfg.maxAttempts) {
      // Poison: surface a definitive failed state to the teacher instead
      // of eternal pending.
      try {
        const logSnap = await db
          .doc(`schools/${claim.schoolId}/readingLogs/${claim.logId}`)
          .get();
        const log = (logSnap.data() ?? {}) as Record<string, unknown>;
        await evalDocRef(db, claim.schoolId, claim.logId).set(
          unscoredEvalDoc({
            schoolId: claim.schoolId,
            logId: claim.logId,
            studentId: claim.studentId,
            classId: claim.classId,
            logDate: log.date instanceof Timestamp ? log.date : null,
            audioUploadedAt:
              log.comprehensionAudioUploadedAt instanceof Timestamp ?
                log.comprehensionAudioUploadedAt :
                null,
          }, cfg, "failed", ["system_error"])
        );
      } catch (evalErr: unknown) {
        functions.logger.error("aiEval.worker.poisonEvalWriteFailed", {
          errorCode: errorCodeForLog(evalErr),
        });
      }
      await incrementDailyMetrics(db, {poisoned: 1}, now);
      return await finish("poisoned", {lastError: reason});
    }
    await incrementDailyMetrics(db, {failed: 1}, now);
    return await finish("failed", {lastError: reason});
  }
}

// ---------------------------------------------------------------------------
// Sweep
// ---------------------------------------------------------------------------

export const SWEEP_STATE_DOC = "aiEvalOpsConfig/sweepState";
export const SWEEP_PAGE_CAP = 120;
export const SWEEP_CONCURRENCY = 8;
export const STALE_QUEUED_MS = 60 * 60 * 1000;
export const BACKLOG_ALERT_RUNS = 3;

export function sydneyDayKey(now: Date): string {
  return now.toLocaleDateString("en-CA", {timeZone: "Australia/Sydney"});
}

// Pure chunked concurrency helper.
export async function runBounded<T>(
  items: T[],
  concurrency: number,
  run: (item: T) => Promise<void>
): Promise<void> {
  for (let i = 0; i < items.length; i += concurrency) {
    await Promise.all(items.slice(i, i + concurrency).map(run));
  }
}

export interface SweepResult {
  selected: number;
  processed: number;
  deferredSwept: boolean;
  backlogRuns: number;
  safetyNetEnqueued: number;
  /** True when the sweep stopped because the platform kill switch is off. */
  platformDisabled?: boolean;
}

export async function sweepAiEvalJobsCore(
  deps: WorkerDeps
): Promise<SweepResult> {
  const {db} = deps;

  // Kill switch FIRST, before any work is selected. processAiEvalJobCore
  // re-checks this at claim time, so nothing could ever have been evaluated
  // with the switch off — but until 2026-07-20 the sweep's safety net still
  // CREATED job docs for entitled schools, each of which triggered a worker
  // that immediately terminated "disabled". Flipping the switch left the
  // queue churning instead of quiescent, which is not what an operator
  // reaching for a kill switch expects to see. Fails closed: a missing or
  // unreadable flag doc stops the sweep.
  const flagSnap = await db.doc(AI_EVALUATION_FLAG_DOC).get();
  if (!flagSnap.exists || !platformAiEvaluationEnabled(flagSnap.data())) {
    return {
      selected: 0,
      processed: 0,
      deferredSwept: false,
      backlogRuns: 0,
      safetyNetEnqueued: 0,
      platformDisabled: true,
    };
  }

  const cfg = await deps.readOpsConfig();
  const now = deps.now();
  const jobIds = new Set<string>();

  // Lost-trigger recovery: stale queued jobs (the only recovery for a
  // dropped onDocumentCreated event under retry:false).
  const staleCutoff = Timestamp.fromMillis(now.getTime() - STALE_QUEUED_MS);
  const stale = await db.collection("aiEvalJobs")
    .where("status", "==", "queued")
    .where("createdAt", "<", staleCutoff)
    .orderBy("createdAt", "asc")
    .limit(SWEEP_PAGE_CAP)
    .get();
  stale.docs.forEach((doc) => jobIds.add(doc.id));

  // Eligible failed (attempts under max — filtered in code).
  const failed = await db.collection("aiEvalJobs")
    .where("status", "==", "failed")
    .orderBy("createdAt", "asc")
    .limit(SWEEP_PAGE_CAP)
    .get();
  failed.docs.forEach((doc) => {
    const attempts = Number(doc.data().attempts ?? 0);
    if (attempts < cfg.maxAttempts) jobIds.add(doc.id);
  });

  // Stuck processing (claimedAt beyond 2x timeout — filtered in code).
  const stuckCutoffMs = cfg.evalTimeoutSec * 1000 * 2 + 300_000;
  const processing = await db.collection("aiEvalJobs")
    .where("status", "==", "processing")
    .orderBy("createdAt", "asc")
    .limit(SWEEP_PAGE_CAP)
    .get();
  processing.docs.forEach((doc) => {
    const claimedAt = doc.data().claimedAt;
    if (
      claimedAt instanceof Timestamp &&
      now.getTime() - claimedAt.toMillis() > stuckCutoffMs
    ) {
      jobIds.add(doc.id);
    }
  });

  // Deferred jobs: only on the first run after the Sydney date rolls, so
  // fresh daily budget exists to absorb them.
  const stateRef = db.doc(SWEEP_STATE_DOC);
  const stateSnap = await stateRef.get();
  const state = (stateSnap.data() ?? {}) as Record<string, unknown>;
  const today = sydneyDayKey(now);
  const deferredSwept = state.lastDeferredSweepDate !== today;
  if (deferredSwept) {
    const deferred = await db.collection("aiEvalJobs")
      .where("status", "==", "deferred")
      .orderBy("createdAt", "asc")
      .limit(SWEEP_PAGE_CAP)
      .get();
    deferred.docs.forEach((doc) => jobIds.add(doc.id));
  }

  const selected = [...jobIds].slice(0, SWEEP_PAGE_CAP);
  let processed = 0;
  await runBounded(selected, SWEEP_CONCURRENCY, async (jobId) => {
    try {
      const terminal =
        await processAiEvalJobCore(deps, jobId, {sweep: true});
      if (terminal !== "not_claimed") processed++;
    } catch (err: unknown) {
      functions.logger.warn("aiEval.sweep.jobFailed", {
        errorCode: errorCodeForLog(err),
      });
    }
  });

  // Safety net: recent uploads in entitled schools with no job doc.
  let safetyNetEnqueued = 0;
  try {
    const entitled = await db.collection("schools")
      .where("settings.aiEvaluation.enabled", "==", true)
      .limit(50)
      .get();
    const cutoff = Timestamp.fromMillis(now.getTime() - 24 * 60 * 60 * 1000);
    for (const school of entitled.docs) {
      // Firestore can only index the bare flag, so re-apply the real gate:
      // a school switched on but never confirmed (or confirmed against
      // superseded terms) must not have jobs minted for it just to have the
      // worker terminate them "disabled".
      if (!schoolAiEvaluationEnabled(school.data())) continue;
      const recent = await db
        .collection(`schools/${school.id}/readingLogs`)
        .where("comprehensionAudioUploadedAt", ">", cutoff)
        .orderBy("comprehensionAudioUploadedAt", "desc")
        .limit(50)
        .get();
      for (const logDoc of recent.docs) {
        const jobRef =
          db.doc(`aiEvalJobs/${school.id}_${logDoc.id}`);
        const jobSnap = await jobRef.get();
        if (jobSnap.exists) continue;
        const log = (logDoc.data() ?? {}) as Record<string, unknown>;
        if (
          log.comprehensionAudioUploaded !== true ||
          log.comprehensionAudioValidationVersion !== AUDIO_VALIDATION_VERSION ||
          typeof log.comprehensionAudioObjectGeneration !== "string" ||
          !(log.comprehensionAudioUploadedAt instanceof Timestamp)
        ) {
          continue;
        }
        try {
          await jobRef.create({
            schoolId: school.id,
            logId: logDoc.id,
            studentId: typeof log.studentId === "string" ? log.studentId : "",
            classId: typeof log.classId === "string" ? log.classId : "",
            status: "queued",
            attempts: 0,
            createdAt: FieldValue.serverTimestamp(),
            sourceUploadedAt: log.comprehensionAudioUploadedAt,
            audioObjectGeneration: log.comprehensionAudioObjectGeneration,
            audioValidationVersion: AUDIO_VALIDATION_VERSION,
            enqueuedBy: "sweep_safety_net",
          });
          safetyNetEnqueued++;
        } catch (err: unknown) {
          // ALREADY_EXISTS race with a live enqueue is fine.
        }
      }
    }
  } catch (err: unknown) {
    functions.logger.warn("aiEval.sweep.safetyNetFailed", {
      errorCode: errorCodeForLog(err),
    });
  }

  // Backlog + cost alarms.
  let backlogRuns = Number(state.backlogRuns ?? 0);
  backlogRuns = selected.length >= SWEEP_PAGE_CAP ? backlogRuns + 1 : 0;
  if (backlogRuns >= BACKLOG_ALERT_RUNS) {
    // Documented Cloud Tasks escalation trigger.
    functions.logger.error("aiEval.sweep.chronicBacklog", {backlogRuns});
  }
  try {
    const metrics = await readDailyMetrics(db, now);
    const costUsd = (metrics.estCostUsdMillis ?? 0) / 1000;
    if (costUsd > cfg.costAlarmDailyUsd) {
      functions.logger.error("aiEval.sweep.costAlarm", {
        costUsd: Math.round(costUsd * 100) / 100,
        costAlarmDailyUsd: cfg.costAlarmDailyUsd,
      });
    }
  } catch (err: unknown) {
    functions.logger.warn("aiEval.sweep.costCheckFailed", {
      errorCode: errorCodeForLog(err),
    });
  }

  await stateRef.set({
    lastRunAt: FieldValue.serverTimestamp(),
    lastDeferredSweepDate: deferredSwept ?
      today :
      state.lastDeferredSweepDate ?? null,
    backlogRuns,
  }, {merge: true});

  return {
    selected: selected.length,
    processed,
    deferredSwept,
    backlogRuns,
    safetyNetEnqueued,
  };
}

// ---------------------------------------------------------------------------
// Deployed functions
// ---------------------------------------------------------------------------

export const processAiEvalJob = onDocumentCreated(
  {
    document: "aiEvalJobs/{jobId}",
    timeoutSeconds: 300,
    memory: "512MiB",
    maxInstances: 5,
    retry: false,
  },
  async (event) => {
    const jobId = event.params.jobId;
    try {
      const terminal =
        await processAiEvalJobCore(defaultWorkerDeps(), jobId);
      functions.logger.info("aiEval.worker.terminal", {terminal});
    } catch (err: unknown) {
      // Claim/terminal bookkeeping failed; the sweep's stale/stuck clauses
      // are the recovery path. Never rethrow under retry:false.
      functions.logger.error("aiEval.worker.unhandled", {
        errorCode: errorCodeForLog(err),
      });
    }
  }
);

export const sweepAiEvalJobs = onSchedule(
  {
    schedule: "0 */6 * * *",
    timeZone: "Australia/Sydney",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    try {
      const result = await sweepAiEvalJobsCore(defaultWorkerDeps());
      functions.logger.info("aiEval.sweep.completed", {
        selected: result.selected,
        processed: result.processed,
        deferredSwept: result.deferredSwept,
        backlogRuns: result.backlogRuns,
        safetyNetEnqueued: result.safetyNetEnqueued,
      });
      await recordCronRun(
        "sweepAiEvalJobs",
        result.backlogRuns >= BACKLOG_ALERT_RUNS ? "error" : "ok",
        `selected=${result.selected} processed=${result.processed}`
      );
    } catch (err: unknown) {
      functions.logger.error("aiEval.sweep.failed", {
        errorCode: errorCodeForLog(err),
      });
      await recordCronRun("sweepAiEvalJobs", "error", errorCodeForLog(err));
    }
  }
);
