// State-machine tests for the AI evaluation worker + sweep, driven through
// an in-memory Firestore stub with fully stubbed providers. No emulator.
const test = require('node:test');
const assert = require('node:assert/strict');
const {Timestamp, FieldValue} = require('firebase-admin/firestore');

const {
  processAiEvalJobCore,
  sweepAiEvalJobsCore,
  runBounded,
  sydneyDayKey,
} = require('../lib/ai_evaluation/worker.js');
const {AI_EVAL_OPS_DEFAULTS, mergeOpsConfig} =
  require('../lib/ai_evaluation/config.js');
const {AUDIO_VALIDATION_VERSION} =
  require('../lib/audio_media_validation.js');

const NOW = new Date('2026-07-19T10:00:00Z');
const UPLOADED_AT = Timestamp.fromDate(new Date('2026-07-19T09:00:00Z'));
const LOG_DATE = Timestamp.fromDate(new Date('2026-07-18T00:00:00Z'));

// ---------------------------------------------------------------------------
// In-memory Firestore stub. FieldValue sentinels are resolved on write:
// serverTimestamp -> Timestamp.now(), delete -> field removal, any other
// transform (increment) -> numeric +1 (all worker increments are +1 where
// the value is later re-read).
// ---------------------------------------------------------------------------
function resolve(current, data) {
  const out = {...(current ?? {})};
  for (const [key, value] of Object.entries(data)) {
    if (value instanceof FieldValue) {
      if (value.isEqual(FieldValue.serverTimestamp())) {
        out[key] = Timestamp.fromDate(new Date());
      } else if (value.isEqual(FieldValue.delete())) {
        delete out[key];
      } else {
        out[key] = (Number(out[key]) || 0) + 1;
      }
    } else {
      out[key] = value;
    }
  }
  return out;
}

function memDb(initial = {}) {
  const store = new Map(Object.entries(initial));
  const writes = [];
  function snapOf(path) {
    const value = store.get(path);
    return {
      exists: value !== undefined,
      id: path.split('/').pop(),
      ref: {path},
      data: () => value,
    };
  }
  function docRef(path) {
    return {
      path,
      get: async () => snapOf(path),
      set: async (data, opts) => {
        const base = opts && opts.merge ? store.get(path) : undefined;
        store.set(path, resolve(base, data));
        writes.push({type: 'set', path, data});
      },
      create: async (data) => {
        if (store.has(path)) {
          const err = new Error('already exists');
          err.code = 6;
          throw err;
        }
        store.set(path, resolve(undefined, data));
        writes.push({type: 'create', path, data});
      },
    };
  }
  function matches(value, op, target) {
    if (op === '==') return value === target;
    const a = value instanceof Timestamp ? value.toMillis() : value;
    const b = target instanceof Timestamp ? target.toMillis() : target;
    if (op === '<') return a < b;
    if (op === '>') return a > b;
    return false;
  }
  function collectionRef(colPath) {
    const filters = [];
    let limitN = Infinity;
    const builder = {
      where: (field, op, target) => {
        filters.push({field, op, target});
        return builder;
      },
      orderBy: () => builder,
      limit: (n) => {
        limitN = n;
        return builder;
      },
      get: async () => {
        const docs = [];
        for (const [path, value] of store.entries()) {
          if (!path.startsWith(`${colPath}/`)) continue;
          if (path.slice(colPath.length + 1).includes('/')) continue;
          const pass = filters.every((f) => {
            const fieldValue = f.field.split('.').reduce(
              (acc, part) => (acc ?? {})[part], value);
            return matches(fieldValue, f.op, f.target);
          });
          if (pass) docs.push(snapOf(path));
          if (docs.length >= limitN) break;
        }
        return {docs, size: docs.length};
      },
    };
    return builder;
  }
  const db = {
    doc: (path) => docRef(path),
    collection: (path) => collectionRef(path),
    runTransaction: async (fn) => fn({
      get: async (ref) => snapOf(ref.path),
      set: (ref, data) => {
        store.set(ref.path, resolve(undefined, data));
        writes.push({type: 'txSet', path: ref.path, data});
      },
      update: (ref, data) => {
        if (!store.has(ref.path)) throw new Error(`missing doc ${ref.path}`);
        store.set(ref.path, resolve(store.get(ref.path), data));
        writes.push({type: 'txUpdate', path: ref.path, data});
      },
      create: (ref, data) => {
        store.set(ref.path, resolve(undefined, data));
        writes.push({type: 'txCreate', path: ref.path, data});
      },
    }),
  };
  return {db, store, writes};
}

const S = 'school1';
const L = 'log1';
const JOB = `aiEvalJobs/${S}_${L}`;
const EVAL = `schools/${S}/comprehensionEvals/${L}`;

function seed(overrides = {}) {
  return {
    'platformConfig/aiEvaluation': {enabled: true},
    [`schools/${S}`]: {settings: {aiEvaluation: {enabled: true}}},
    [JOB]: {
      schoolId: S, logId: L, studentId: 'stu1', classId: 'c1',
      status: 'queued', attempts: 0,
      createdAt: Timestamp.fromDate(new Date('2026-07-19T09:01:00Z')),
      sourceUploadedAt: UPLOADED_AT,
      audioObjectGeneration: 'gen-1',
      audioValidationVersion: AUDIO_VALIDATION_VERSION,
    },
    [`schools/${S}/readingLogs/${L}`]: {
      studentId: 'stu1', classId: 'c1', date: LOG_DATE,
      comprehensionAudioUploaded: true,
      comprehensionAudioUploadedAt: UPLOADED_AT,
      comprehensionAudioObjectGeneration: 'gen-1',
      comprehensionAudioValidationVersion: AUDIO_VALIDATION_VERSION,
      comprehensionAudioDurationSec: 30,
      comprehensionQuestionText: 'What happened at the start?',
    },
    [`schools/${S}/students/stu1`]: {name: 'Milo Smith'},
    ...overrides,
  };
}

function goodEvalParsed() {
  return {
    summary: 'The student recalled the opening event clearly.',
    criterionScores: [
      {criterionId: 'recall', score: 2, evidence: 'the dog found a bone'},
      {criterionId: 'sequence', score: 2, evidence: 'and then he buried it'},
      {criterionId: 'detail', score: 1, evidence: 'near the tree'},
    ],
    overallLevel: 'developing',
    confidence: 'high',
    flags: [],
    assessable: true,
  };
}

function deps(db, overrides = {}) {
  const calls = {transcribe: [], classify: [], evaluate: []};
  const built = {
    db,
    readOpsConfig: async () => mergeOpsConfig(overrides.cfg),
    transcribe: async (params) => {
      calls.transcribe.push(params);
      if (overrides.transcribe) return overrides.transcribe(params);
      return {
        transcript: 'um the dog found a bone and Milo buried it',
        confidence: 0.95,
        billedSec: 31,
      };
    },
    classify: async (dbArg, params) => {
      calls.classify.push(params);
      return {
        categories: ['literal_recall'], rubricKey: 'literal_recall',
        fromCache: true, fromFallback: false, usedLlmCall: false,
      };
    },
    evaluate: async (request) => {
      calls.evaluate.push(request);
      if (overrides.evaluate) return overrides.evaluate(request);
      return {
        kind: 'ok',
        parsed: goodEvalParsed(),
        usage: {
          inputTokens: 900, outputTokens: 300,
          thoughtsTokens: 0, cachedTokens: 0,
        },
      };
    },
    now: () => NOW,
  };
  return {deps: built, calls};
}

test('worker: full success path writes a complete eval', async () => {
  const {db, store} = memDb(seed());
  const {deps: d, calls} = deps(db);
  const terminal = await processAiEvalJobCore(d, `${S}_${L}`);
  assert.equal(terminal, 'done');
  const job = store.get(JOB);
  assert.equal(job.status, 'done');
  const evalDoc = store.get(EVAL);
  assert.equal(evalDoc.status, 'complete');
  assert.equal(evalDoc.overallLevel, 'developing');
  assert.equal(evalDoc.questionSource, 'log');
  assert.equal(evalDoc.questionTextUsed, 'What happened at the start?');
  assert.equal(evalDoc.rubricKey, 'literal_recall');
  assert.equal(evalDoc.assessable, true);
  assert.equal(evalDoc.sortKey, 56);
  assert.ok(evalDoc.audioUploadedAt.isEqual(UPLOADED_AT));
  // Redaction: the provider never saw the registered name.
  assert.ok(!calls.evaluate[0].transcript.includes('Milo'));
  assert.ok(calls.evaluate[0].transcript.includes('[the student]'));
  // Metering happened (school monthly usage doc written).
  assert.ok(store.get(`schools/${S}/meta/aiEvalUsage`));
});

test('worker: not claimed for missing or terminal jobs', async () => {
  const {db} = memDb(seed({[JOB]: {status: 'done', schoolId: S, logId: L}}));
  const {deps: d} = deps(db);
  assert.equal(await processAiEvalJobCore(d, `${S}_${L}`), 'not_claimed');
  assert.equal(await processAiEvalJobCore(d, 'nope_nope'), 'not_claimed');
});

test('worker: kill switch off at claim => disabled without spend', async () => {
  const {db, store} = memDb(seed({
    'platformConfig/aiEvaluation': {enabled: false},
  }));
  const {deps: d, calls} = deps(db);
  assert.equal(await processAiEvalJobCore(d, `${S}_${L}`), 'disabled');
  assert.equal(store.get(JOB).doneReason, 'disabled');
  assert.equal(calls.transcribe.length, 0);
  assert.equal(store.get(EVAL), undefined);
});

test('worker: school entitlement off => disabled', async () => {
  const {db} = memDb(seed({[`schools/${S}`]: {settings: {}}}));
  const {deps: d} = deps(db);
  assert.equal(await processAiEvalJobCore(d, `${S}_${L}`), 'disabled');
});

test('worker: non-allowlisted model defers config_invalid', async () => {
  const {db, store} = memDb(seed());
  const {deps: d, calls} = deps(db, {cfg: {model: 'gemini-9-mystery'}});
  assert.equal(
    await processAiEvalJobCore(d, `${S}_${L}`), 'deferred:config_invalid');
  assert.equal(store.get(JOB).status, 'deferred');
  assert.equal(store.get(JOB).deferredReason, 'config_invalid');
  assert.equal(calls.transcribe.length, 0);
});

test('worker: deleted log => done log_deleted', async () => {
  const {db, store} = memDb(seed());
  store.delete(`schools/${S}/readingLogs/${L}`);
  const {deps: d} = deps(db);
  assert.equal(await processAiEvalJobCore(d, `${S}_${L}`), 'log_deleted');
  assert.equal(store.get(JOB).doneReason, 'log_deleted');
});

test('worker: stale receipt => eval skipped audio_unavailable', async () => {
  const {db, store} = memDb(seed());
  store.set(`schools/${S}/readingLogs/${L}`, {
    ...store.get(`schools/${S}/readingLogs/${L}`),
    comprehensionAudioValidationVersion: 'header-only-v0',
  });
  const {deps: d, calls} = deps(db);
  assert.equal(await processAiEvalJobCore(d, `${S}_${L}`), 'done');
  assert.equal(store.get(EVAL).status, 'skipped');
  assert.deepEqual(store.get(EVAL).flags, ['audio_unavailable']);
  assert.equal(calls.transcribe.length, 0);
});

test('worker: too-short recording flagged without STT spend', async () => {
  const {db, store} = memDb(seed());
  store.set(`schools/${S}/readingLogs/${L}`, {
    ...store.get(`schools/${S}/readingLogs/${L}`),
    comprehensionAudioDurationSec: 2,
  });
  const {deps: d, calls} = deps(db);
  assert.equal(await processAiEvalJobCore(d, `${S}_${L}`), 'done');
  assert.equal(store.get(EVAL).status, 'flagged');
  assert.deepEqual(store.get(EVAL).flags, ['too_short']);
  assert.equal(calls.transcribe.length, 0);
});

test('worker: school cap exhausted defers school_cap', async () => {
  const {db, store} = memDb(seed({
    [`schools/${S}/adminMeta/aiEvaluation`]: {capPerDay: 0},
  }));
  const {deps: d, calls} = deps(db);
  assert.equal(
    await processAiEvalJobCore(d, `${S}_${L}`), 'deferred:school_cap');
  assert.equal(store.get(JOB).deferredReason, 'school_cap');
  assert.equal(calls.transcribe.length, 0);
});

test('worker: global cap exhausted defers global_cap', async () => {
  const {db} = memDb(seed());
  const {deps: d} = deps(db, {cfg: {globalDailyCap: 0.5}});
  assert.equal(
    await processAiEvalJobCore(d, `${S}_${L}`), 'deferred:global_cap');
});

test('worker: STT quota defers, audio-missing skips, other errors retry',
  async () => {
    const {SttQuotaError, AudioUnavailableError} =
      require('../lib/ai_evaluation/transcription.js');
    {
      const {db} = memDb(seed());
      const {deps: d} = deps(db, {
        transcribe: () => {
          throw new SttQuotaError('quota');
        },
      });
      assert.equal(
        await processAiEvalJobCore(d, `${S}_${L}`), 'deferred:stt_quota');
    }
    {
      const {db, store} = memDb(seed());
      const {deps: d} = deps(db, {
        transcribe: () => {
          throw new AudioUnavailableError('gone');
        },
      });
      assert.equal(await processAiEvalJobCore(d, `${S}_${L}`), 'done');
      assert.equal(store.get(EVAL).status, 'skipped');
    }
    {
      const {db, store} = memDb(seed());
      const {deps: d} = deps(db, {
        transcribe: () => {
          throw new Error('socket reset');
        },
      });
      assert.equal(await processAiEvalJobCore(d, `${S}_${L}`), 'failed');
      assert.equal(store.get(JOB).status, 'failed');
      assert.ok(store.get(JOB).lastError);
    }
  });

test('worker: empty transcript flagged inaudible, no LLM call', async () => {
  const {db, store} = memDb(seed());
  const {deps: d, calls} = deps(db, {
    transcribe: () => ({transcript: '  ', confidence: 1, billedSec: 5}),
  });
  assert.equal(await processAiEvalJobCore(d, `${S}_${L}`), 'done');
  assert.equal(store.get(EVAL).status, 'flagged');
  assert.deepEqual(store.get(EVAL).flags, ['inaudible']);
  assert.equal(calls.evaluate.length, 0);
});

test('worker: low STT confidence adds the flag but still evaluates',
  async () => {
    const {db, store} = memDb(seed());
    const {deps: d, calls} = deps(db, {
      transcribe: () => ({
        transcript: 'mumbled words', confidence: 0.3, billedSec: 10,
      }),
    });
    assert.equal(await processAiEvalJobCore(d, `${S}_${L}`), 'done');
    assert.equal(calls.evaluate.length, 1);
    assert.ok(store.get(EVAL).flags.includes('low_stt_confidence'));
    assert.equal(store.get(EVAL).status, 'flagged');
  });

test('worker: question falls back to current class question then default',
  async () => {
    {
      const {db, store} = memDb(seed());
      const log = store.get(`schools/${S}/readingLogs/${L}`);
      delete log.comprehensionQuestionText;
      store.set(`schools/${S}/classes/c1`, {
        settings: {comprehensionQuestion: 'Who was the villain?'},
      });
      const {deps: d} = deps(db);
      await processAiEvalJobCore(d, `${S}_${L}`);
      assert.equal(store.get(EVAL).questionSource, 'classCurrent');
      assert.equal(store.get(EVAL).questionTextUsed, 'Who was the villain?');
    }
    {
      const {db, store} = memDb(seed());
      const log = store.get(`schools/${S}/readingLogs/${L}`);
      delete log.comprehensionQuestionText;
      const {deps: d} = deps(db);
      await processAiEvalJobCore(d, `${S}_${L}`);
      assert.equal(store.get(EVAL).questionSource, 'default');
    }
  });

test('worker: safety block => flagged concerning_content', async () => {
  const {db, store} = memDb(seed());
  const {deps: d} = deps(db, {
    evaluate: () => ({kind: 'safety_blocked', reason: 'SAFETY'}),
  });
  assert.equal(await processAiEvalJobCore(d, `${S}_${L}`), 'done');
  assert.ok(store.get(EVAL).flags.includes('concerning_content'));
  assert.equal(store.get(EVAL).status, 'flagged');
  assert.equal(store.get(EVAL).assessable, false);
});

test('worker: recitation => flagged recitation_blocked', async () => {
  const {db, store} = memDb(seed());
  const {deps: d} = deps(db, {evaluate: () => ({kind: 'recitation'})});
  assert.equal(await processAiEvalJobCore(d, `${S}_${L}`), 'done');
  assert.ok(store.get(EVAL).flags.includes('recitation_blocked'));
});

test('worker: provider quota => deferred provider_quota', async () => {
  const {db, store} = memDb(seed());
  const {deps: d} = deps(db, {evaluate: () => ({kind: 'quota'})});
  assert.equal(
    await processAiEvalJobCore(d, `${S}_${L}`), 'deferred:provider_quota');
  assert.equal(store.get(EVAL), undefined);
});

test('worker: invalid model response retries, poisons at max attempts',
  async () => {
    {
      const {db, store} = memDb(seed());
      const {deps: d} = deps(db, {
        evaluate: () => ({
          kind: 'ok', parsed: {bogus: true},
          usage: {inputTokens: 1, outputTokens: 1, thoughtsTokens: 0, cachedTokens: 0},
        }),
      });
      assert.equal(await processAiEvalJobCore(d, `${S}_${L}`), 'failed');
      assert.ok(store.get(JOB).lastError.startsWith('invalid_response'));
    }
    {
      const {db, store} = memDb(seed());
      const job = store.get(JOB);
      job.attempts = 2; // claim makes it 3 == maxAttempts
      const {deps: d} = deps(db, {
        evaluate: () => ({kind: 'retryable', reason: 'provider_http_500'}),
      });
      assert.equal(await processAiEvalJobCore(d, `${S}_${L}`), 'poisoned');
      assert.equal(store.get(JOB).status, 'poisoned');
      assert.equal(store.get(EVAL).status, 'failed');
      assert.deepEqual(store.get(EVAL).flags, ['system_error']);
    }
  });

test('worker: mid-flight re-upload leaves the job queued for re-run',
  async () => {
    const {db, store} = memDb(seed());
    const newer = Timestamp.fromDate(new Date('2026-07-19T09:30:00Z'));
    const {deps: d} = deps(db, {
      evaluate: () => {
        // Simulate a re-upload enqueue reset landing mid-processing.
        const job = store.get(JOB);
        store.set(JOB, {...job, sourceUploadedAt: newer, status: 'queued'});
        return {
          kind: 'ok', parsed: goodEvalParsed(),
          usage: {inputTokens: 1, outputTokens: 1, thoughtsTokens: 0, cachedTokens: 0},
        };
      },
    });
    assert.equal(await processAiEvalJobCore(d, `${S}_${L}`), 'done');
    // The terminal update must NOT clobber the newer queued job.
    assert.equal(store.get(JOB).status, 'queued');
  });

// ---------------------------------------------------------------------------
// Sweep
// ---------------------------------------------------------------------------

function sweepSeed(jobs) {
  const base = {
    'platformConfig/aiEvaluation': {enabled: true},
    [`schools/${S}`]: {settings: {aiEvaluation: {enabled: true}}},
    'aiEvalOpsConfig/sweepState': {
      lastDeferredSweepDate: sydneyDayKey(NOW),
      backlogRuns: 0,
    },
  };
  for (const [id, job] of Object.entries(jobs)) {
    base[`aiEvalJobs/${id}`] = job;
  }
  return base;
}

function staleJob(overrides = {}) {
  return {
    schoolId: S, logId: L, studentId: 'stu1', classId: 'c1',
    status: 'queued', attempts: 0,
    createdAt: Timestamp.fromDate(new Date('2026-07-19T07:00:00Z')),
    sourceUploadedAt: UPLOADED_AT,
    ...overrides,
  };
}

test('sweep: recovers stale queued jobs, leaves fresh ones', async () => {
  const {db, store} = memDb({
    ...sweepSeed({
      [`${S}_${L}`]: staleJob(),
      [`${S}_fresh`]: staleJob({
        logId: 'fresh',
        createdAt: Timestamp.fromDate(new Date('2026-07-19T09:59:00Z')),
      }),
    }),
    [`schools/${S}/readingLogs/${L}`]: {
      studentId: 'stu1', classId: 'c1', date: LOG_DATE,
      comprehensionAudioUploaded: true,
      comprehensionAudioUploadedAt: UPLOADED_AT,
      comprehensionAudioObjectGeneration: 'gen-1',
      comprehensionAudioValidationVersion: AUDIO_VALIDATION_VERSION,
      comprehensionAudioDurationSec: 30,
      comprehensionQuestionText: 'Q?',
    },
    [`schools/${S}/students/stu1`]: {name: 'Milo'},
  });
  const {deps: d} = deps(db);
  const result = await sweepAiEvalJobsCore(d);
  assert.equal(result.selected, 1);
  assert.equal(result.processed, 1);
  assert.equal(store.get(JOB).status, 'done');
  assert.equal(store.get(`aiEvalJobs/${S}_fresh`).status, 'queued');
});

test('sweep: retries eligible failed jobs only', async () => {
  const {db, store} = memDb({
    ...sweepSeed({
      [`${S}_retry`]: staleJob({logId: 'retry', status: 'failed', attempts: 1}),
      [`${S}_spent`]: staleJob({logId: 'spent', status: 'failed', attempts: 3}),
    }),
    [`schools/${S}/readingLogs/retry`]: {
      studentId: 'stu1', classId: 'c1', date: LOG_DATE,
      comprehensionAudioUploaded: true,
      comprehensionAudioUploadedAt: UPLOADED_AT,
      comprehensionAudioObjectGeneration: 'gen-1',
      comprehensionAudioValidationVersion: AUDIO_VALIDATION_VERSION,
      comprehensionAudioDurationSec: 30,
      comprehensionQuestionText: 'Q?',
    },
    [`schools/${S}/students/stu1`]: {name: 'Milo'},
  });
  const {deps: d} = deps(db);
  const result = await sweepAiEvalJobsCore(d);
  assert.equal(result.selected, 1);
  assert.equal(store.get(`aiEvalJobs/${S}_retry`).status, 'done');
  assert.equal(store.get(`aiEvalJobs/${S}_spent`).status, 'failed');
});

test('sweep: deferred jobs only re-run after the Sydney date rolls',
  async () => {
    const deferredJob = staleJob({status: 'deferred'});
    {
      // Same Sydney day: deferred not selected.
      const {db} = memDb(sweepSeed({[`${S}_${L}`]: deferredJob}));
      const {deps: d} = deps(db);
      const result = await sweepAiEvalJobsCore(d);
      assert.equal(result.deferredSwept, false);
      assert.equal(result.selected, 0);
    }
    {
      // New day: deferred selected.
      const seeded = sweepSeed({[`${S}_${L}`]: deferredJob});
      seeded['aiEvalOpsConfig/sweepState'] = {
        lastDeferredSweepDate: '2026-07-18', backlogRuns: 0,
      };
      seeded[`schools/${S}/readingLogs/${L}`] = {
        studentId: 'stu1', classId: 'c1', date: LOG_DATE,
        comprehensionAudioUploaded: true,
        comprehensionAudioUploadedAt: UPLOADED_AT,
        comprehensionAudioObjectGeneration: 'gen-1',
        comprehensionAudioValidationVersion: AUDIO_VALIDATION_VERSION,
        comprehensionAudioDurationSec: 30,
        comprehensionQuestionText: 'Q?',
      };
      seeded[`schools/${S}/students/stu1`] = {name: 'Milo'};
      const {db, store} = memDb(seeded);
      const {deps: d} = deps(db);
      const result = await sweepAiEvalJobsCore(d);
      assert.equal(result.deferredSwept, true);
      assert.equal(result.selected, 1);
      assert.equal(store.get(JOB).status, 'done');
      assert.equal(
        store.get('aiEvalOpsConfig/sweepState').lastDeferredSweepDate,
        sydneyDayKey(NOW));
    }
  });

test('sweep: safety net enqueues recent uploads missing a job', async () => {
  const seeded = sweepSeed({});
  seeded[`schools/${S}/readingLogs/orphan`] = {
    studentId: 'stu1', classId: 'c1', date: LOG_DATE,
    comprehensionAudioUploaded: true,
    comprehensionAudioUploadedAt: Timestamp.fromDate(
      new Date('2026-07-19T08:00:00Z')),
    comprehensionAudioObjectGeneration: 'gen-9',
    comprehensionAudioValidationVersion: AUDIO_VALIDATION_VERSION,
    comprehensionAudioDurationSec: 30,
  };
  seeded[`schools/${S}/readingLogs/old`] = {
    studentId: 'stu1', classId: 'c1',
    comprehensionAudioUploaded: true,
    comprehensionAudioUploadedAt: Timestamp.fromDate(
      new Date('2026-07-10T08:00:00Z')),
    comprehensionAudioObjectGeneration: 'gen-8',
    comprehensionAudioValidationVersion: AUDIO_VALIDATION_VERSION,
  };
  const {db, store} = memDb(seeded);
  const {deps: d} = deps(db);
  const result = await sweepAiEvalJobsCore(d);
  assert.equal(result.safetyNetEnqueued, 1);
  const job = store.get(`aiEvalJobs/${S}_orphan`);
  assert.equal(job.status, 'queued');
  assert.equal(job.enqueuedBy, 'sweep_safety_net');
  assert.equal(store.get(`aiEvalJobs/${S}_old`), undefined);
});

test('runBounded chunks work with bounded concurrency', async () => {
  let peak = 0;
  let active = 0;
  const seen = [];
  await runBounded([1, 2, 3, 4, 5, 6, 7], 3, async (n) => {
    active++;
    peak = Math.max(peak, active);
    await new Promise((resolve) => setTimeout(resolve, 5));
    seen.push(n);
    active--;
  });
  assert.equal(seen.length, 7);
  assert.ok(peak <= 3);
});

test('ops defaults are the documented values', () => {
  assert.equal(AI_EVAL_OPS_DEFAULTS.defaultDailyCapPerSchool, 200);
  assert.equal(AI_EVAL_OPS_DEFAULTS.evalRetentionDays, 730);
  assert.equal(AI_EVAL_OPS_DEFAULTS.transcriptRetentionDays, 90);
  assert.equal(AI_EVAL_OPS_DEFAULTS.maxAttempts, 3);
});
