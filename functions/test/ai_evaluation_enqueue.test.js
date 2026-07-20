// Unit tests for the AI evaluation Phase 2 enqueue slice: gates, question
// snapshot helpers and the enqueue core driven through a hand-rolled
// Firestore stub. No emulator required.
const test = require("node:test");
const assert = require("node:assert/strict");
const {Timestamp} = require("firebase-admin/firestore");

const {
  platformAiEvaluationEnabled,
  schoolAiEvaluationEnabled,
  AI_EVALUATION_FLAG_DOC,
  AI_EVAL_AUTHORITY_VERSION,
} = require("../lib/ai_evaluation/gates.js");

// A school entitlement that actually opens the gate: the switch plus current,
// stamped authority evidence. `{enabled: true}` alone no longer entitles.
const ENTITLED = {
  enabled: true,
  authorityVersion: AI_EVAL_AUTHORITY_VERSION,
  authorityConfirmedAt: Timestamp.fromDate(new Date("2026-07-20T00:00:00Z")),
};
const {
  DEFAULT_COMPREHENSION_QUESTION,
  MAX_COMPREHENSION_QUESTION_CHARS,
  clampComprehensionQuestion,
  classComprehensionQuestion,
} = require("../lib/ai_evaluation/question.js");
const {
  aiEvalJobId,
  buildAiEvalJobData,
  shouldResetExistingJob,
  enqueueAiEvalJobCore,
} = require("../lib/ai_evaluation/enqueue.js");
const {AUDIO_VALIDATION_VERSION} =
  require("../lib/audio_media_validation.js");

test("platform gate fails closed on anything but enabled:true", () => {
  assert.equal(platformAiEvaluationEnabled(undefined), false);
  assert.equal(platformAiEvaluationEnabled(null), false);
  assert.equal(platformAiEvaluationEnabled({}), false);
  assert.equal(platformAiEvaluationEnabled({enabled: false}), false);
  assert.equal(platformAiEvaluationEnabled({enabled: "true"}), false);
  assert.equal(platformAiEvaluationEnabled({enabled: 1}), false);
  assert.equal(platformAiEvaluationEnabled({enabled: true}), true);
});

test("school gate fails closed on missing/malformed settings", () => {
  assert.equal(schoolAiEvaluationEnabled(undefined), false);
  assert.equal(schoolAiEvaluationEnabled({}), false);
  assert.equal(schoolAiEvaluationEnabled({settings: null}), false);
  assert.equal(schoolAiEvaluationEnabled({settings: {}}), false);
  assert.equal(
    schoolAiEvaluationEnabled({settings: {aiEvaluation: {}}}),
    false
  );
  assert.equal(
    schoolAiEvaluationEnabled({settings: {aiEvaluation: {enabled: "yes"}}}),
    false
  );
  assert.equal(
    schoolAiEvaluationEnabled({settings: {aiEvaluation: ENTITLED}}),
    true
  );
});

test("school gate requires current, stamped authority evidence", () => {
  // The switch alone is not entitlement.
  assert.equal(
    schoolAiEvaluationEnabled({settings: {aiEvaluation: {enabled: true}}}),
    false
  );
  // What the pilot school actually held in prod before 2026-07-20: the free
  // text box accepted any non-empty string, so its "accepted terms" was the
  // field's own label.
  assert.equal(
    schoolAiEvaluationEnabled({
      settings: {
        aiEvaluation: {
          enabled: true,
          termsVersionAccepted: "Terms version accepted",
        },
      },
    }),
    false
  );
  // Superseded terms fall out of entitlement until re-confirmed.
  assert.equal(
    schoolAiEvaluationEnabled({
      settings: {
        aiEvaluation: {
          ...ENTITLED,
          authorityVersion: "school-ai-eval-v0-2026-01-01",
        },
      },
    }),
    false
  );
  // Version without a confirmation stamp.
  assert.equal(
    schoolAiEvaluationEnabled({
      settings: {
        aiEvaluation: {
          enabled: true,
          authorityVersion: AI_EVAL_AUTHORITY_VERSION,
        },
      },
    }),
    false
  );
  // Confirmed but switched off.
  assert.equal(
    schoolAiEvaluationEnabled({
      settings: {aiEvaluation: {...ENTITLED, enabled: false}},
    }),
    false
  );
});

test("question clamp: default fallback, trim and 200-char cap", () => {
  assert.equal(clampComprehensionQuestion(undefined),
    DEFAULT_COMPREHENSION_QUESTION);
  assert.equal(clampComprehensionQuestion(null),
    DEFAULT_COMPREHENSION_QUESTION);
  assert.equal(clampComprehensionQuestion("   "),
    DEFAULT_COMPREHENSION_QUESTION);
  assert.equal(clampComprehensionQuestion(42),
    DEFAULT_COMPREHENSION_QUESTION);
  assert.equal(clampComprehensionQuestion("  Why did the fox run? "),
    "Why did the fox run?");
  const long = "q".repeat(500);
  assert.equal(clampComprehensionQuestion(long).length,
    MAX_COMPREHENSION_QUESTION_CHARS);
});

test("class question extraction tolerates malformed class docs", () => {
  assert.equal(classComprehensionQuestion(undefined),
    DEFAULT_COMPREHENSION_QUESTION);
  assert.equal(classComprehensionQuestion({settings: "bad"}),
    DEFAULT_COMPREHENSION_QUESTION);
  assert.equal(
    classComprehensionQuestion(
      {settings: {comprehensionQuestion: "What was the best bit?"}}),
    "What was the best bit?"
  );
});

test("job id is schoolId_logId", () => {
  assert.equal(aiEvalJobId("s1", "l1"), "s1_l1");
});

test("job data shape", () => {
  const at = Timestamp.fromMillis(1000);
  const data = buildAiEvalJobData({
    schoolId: "s1", logId: "l1", studentId: "stu", classId: "c1",
    sourceUploadedAt: at, audioObjectGeneration: "g1",
    audioValidationVersion: AUDIO_VALIDATION_VERSION,
  });
  assert.equal(data.status, "queued");
  assert.equal(data.attempts, 0);
  assert.equal(data.schoolId, "s1");
  assert.equal(data.logId, "l1");
  assert.equal(data.studentId, "stu");
  assert.equal(data.classId, "c1");
  assert.equal(data.sourceUploadedAt, at);
  assert.equal(data.audioObjectGeneration, "g1");
  assert.equal(data.audioValidationVersion, AUDIO_VALIDATION_VERSION);
  assert.ok(data.createdAt);
});

test("reset decision: only an older existing job is reset", () => {
  const older = Timestamp.fromMillis(1000);
  const newer = Timestamp.fromMillis(2000);
  assert.equal(shouldResetExistingJob(undefined, newer), true);
  assert.equal(shouldResetExistingJob({}, newer), true);
  assert.equal(
    shouldResetExistingJob({sourceUploadedAt: "not-a-ts"}, newer), true);
  assert.equal(
    shouldResetExistingJob({sourceUploadedAt: older}, newer), true);
  assert.equal(
    shouldResetExistingJob({sourceUploadedAt: newer}, newer), false);
  assert.equal(
    shouldResetExistingJob({sourceUploadedAt: newer}, older), false);
});

// ---------------------------------------------------------------------------
// Enqueue core against a hand-rolled Firestore stub.
// ---------------------------------------------------------------------------

const UPLOADED_AT = Timestamp.fromMillis(5_000_000);

function validLogData(overrides = {}) {
  return Object.assign({
    studentId: "stu-1",
    classId: "class-1",
    comprehensionAudioUploaded: true,
    comprehensionAudioUploadedAt: UPLOADED_AT,
    comprehensionAudioObjectGeneration: "gen-77",
    comprehensionAudioValidationVersion: AUDIO_VALIDATION_VERSION,
  }, overrides);
}

/**
 * Minimal Firestore stub: routes doc paths to canned {exists, data} pairs,
 * records create/update calls, and can simulate ALREADY_EXISTS on create.
 */
function stubDb({platform, school, log, existingJob, createError} = {}) {
  const calls = {creates: [], txCreates: [], txUpdates: []};
  const docs = {
    [AI_EVALUATION_FLAG_DOC]: platform,
    "schools/s1": school,
    "schools/s1/readingLogs/l1": log,
    "aiEvalJobs/s1_l1": existingJob,
  };
  function snapFor(value) {
    return {
      exists: value !== undefined && value !== null,
      data: () => value ?? undefined,
    };
  }
  function docRef(path) {
    return {
      path,
      get: async () => snapFor(docs[path]),
      create: async (data) => {
        if (createError) throw createError;
        calls.creates.push({path, data});
      },
    };
  }
  const db = {
    doc: (path) => docRef(path),
    runTransaction: async (fn) => fn({
      get: async (ref) => snapFor(docs[ref.path]),
      create: (ref, data) => calls.txCreates.push({path: ref.path, data}),
      update: (ref, data) => calls.txUpdates.push({path: ref.path, data}),
    }),
  };
  return {db, calls};
}

function alreadyExistsError() {
  const err = new Error("already exists");
  err.code = 6;
  return err;
}

test("enqueue: platform gate closed (missing doc) skips", async () => {
  const {db, calls} = stubDb({school: {settings: {aiEvaluation: ENTITLED}}, log: validLogData()});
  const outcome = await enqueueAiEvalJobCore(db, {schoolId: "s1", logId: "l1"});
  assert.equal(outcome, "skipped:platform_disabled");
  assert.equal(calls.creates.length, 0);
});

test("enqueue: platform on, school gate closed skips", async () => {
  const {db, calls} = stubDb({
    platform: {enabled: true},
    school: {settings: {}},
    log: validLogData(),
  });
  const outcome = await enqueueAiEvalJobCore(db, {schoolId: "s1", logId: "l1"});
  assert.equal(outcome, "skipped:school_disabled");
  assert.equal(calls.creates.length, 0);
});

test("enqueue: gates open + valid receipt creates the job", async () => {
  const {db, calls} = stubDb({
    platform: {enabled: true},
    school: {settings: {aiEvaluation: ENTITLED}},
    log: validLogData(),
  });
  const outcome = await enqueueAiEvalJobCore(db, {schoolId: "s1", logId: "l1"});
  assert.equal(outcome, "queued");
  assert.equal(calls.creates.length, 1);
  assert.equal(calls.creates[0].path, "aiEvalJobs/s1_l1");
  assert.equal(calls.creates[0].data.status, "queued");
  assert.equal(calls.creates[0].data.audioObjectGeneration, "gen-77");
});

test("enqueue: legacy/invalid receipt is never processed", async () => {
  const bad = [
    validLogData({comprehensionAudioUploaded: false}),
    validLogData({comprehensionAudioValidationVersion: "header-only-v0"}),
    validLogData({comprehensionAudioObjectGeneration: ""}),
    validLogData({comprehensionAudioUploadedAt: "2026-01-01"}),
  ];
  for (const log of bad) {
    const {db, calls} = stubDb({
      platform: {enabled: true},
      school: {settings: {aiEvaluation: ENTITLED}},
      log,
    });
    const outcome =
      await enqueueAiEvalJobCore(db, {schoolId: "s1", logId: "l1"});
    assert.equal(outcome, "skipped:invalid_receipt");
    assert.equal(calls.creates.length, 0);
  }
});

test("enqueue: teacher-proxy logs cannot reach enqueue with ids missing", async () => {
  // Teacher-proxy recordings are rejected upstream by the confirm callable;
  // structurally the enqueue also refuses any log without student/class ids.
  const {db, calls} = stubDb({
    platform: {enabled: true},
    school: {settings: {aiEvaluation: ENTITLED}},
    log: validLogData({studentId: ""}),
  });
  const outcome = await enqueueAiEvalJobCore(db, {schoolId: "s1", logId: "l1"});
  assert.equal(outcome, "skipped:invalid_log");
  assert.equal(calls.creates.length, 0);
});

test("enqueue: missing log skips", async () => {
  const {db} = stubDb({
    platform: {enabled: true},
    school: {settings: {aiEvaluation: ENTITLED}},
  });
  const outcome = await enqueueAiEvalJobCore(db, {schoolId: "s1", logId: "l1"});
  assert.equal(outcome, "skipped:log_missing");
});

test("enqueue: ALREADY_EXISTS with older job resets it to queued", async () => {
  const {db, calls} = stubDb({
    platform: {enabled: true},
    school: {settings: {aiEvaluation: ENTITLED}},
    log: validLogData(),
    existingJob: {
      status: "done",
      attempts: 3,
      sourceUploadedAt: Timestamp.fromMillis(1_000_000),
    },
    createError: alreadyExistsError(),
  });
  const outcome = await enqueueAiEvalJobCore(db, {schoolId: "s1", logId: "l1"});
  assert.equal(outcome, "reset");
  assert.equal(calls.txUpdates.length, 1);
  const update = calls.txUpdates[0].data;
  assert.equal(update.status, "queued");
  assert.equal(update.attempts, 0);
  assert.equal(update.sourceUploadedAt, UPLOADED_AT);
});

test("enqueue: ALREADY_EXISTS with same-or-newer job is left alone", async () => {
  const {db, calls} = stubDb({
    platform: {enabled: true},
    school: {settings: {aiEvaluation: ENTITLED}},
    log: validLogData(),
    existingJob: {status: "processing", sourceUploadedAt: UPLOADED_AT},
    createError: alreadyExistsError(),
  });
  const outcome = await enqueueAiEvalJobCore(db, {schoolId: "s1", logId: "l1"});
  assert.equal(outcome, "skipped:existing_newer");
  assert.equal(calls.txUpdates.length, 0);
});

test("enqueue: unexpected create error propagates to the caller", async () => {
  const boom = new Error("firestore unavailable");
  boom.code = 14;
  const {db} = stubDb({
    platform: {enabled: true},
    school: {settings: {aiEvaluation: ENTITLED}},
    log: validLogData(),
    createError: boom,
  });
  await assert.rejects(
    () => enqueueAiEvalJobCore(db, {schoolId: "s1", logId: "l1"}),
    /firestore unavailable/
  );
});
