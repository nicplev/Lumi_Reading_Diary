// Unit tests for AI evaluation retention (Phase 4) using the shared
// in-memory Firestore stub.
const test = require('node:test');
const assert = require('node:assert/strict');
const {Timestamp} = require('firebase-admin/firestore');
const {memDb} = require('./helpers/mem_firestore.js');

const {
  clearExpiredTranscripts,
  deleteExpiredEvals,
  deleteExpiredClassifications,
  runAiEvalRetention,
  RETENTION_STATE_DOC,
} = require('../lib/ai_evaluation/retention.js');
const {AI_EVAL_OPS_DEFAULTS} = require('../lib/ai_evaluation/config.js');

const NOW = new Date('2026-07-19T10:00:00Z');
const DAY_MS = 86_400_000;

function ts(daysAgo) {
  return Timestamp.fromMillis(NOW.getTime() - daysAgo * DAY_MS);
}

function evalDoc(daysAgo, extra = {}) {
  return {
    schoolId: 's1',
    evaluatedAt: ts(daysAgo),
    transcript: 'the dog found a bone',
    summary: 'ok',
    ...extra,
  };
}

test('transcripts cleared after the retention window, cursor advances',
  async () => {
    const {db, store} = memDb({
      'schools/s1/comprehensionEvals/old1': evalDoc(120),
      'schools/s1/comprehensionEvals/old2': evalDoc(100),
      'schools/s1/comprehensionEvals/fresh': evalDoc(10),
    });
    const cleared =
      await clearExpiredTranscripts(db, AI_EVAL_OPS_DEFAULTS, NOW);
    assert.equal(cleared, 2);
    const old1 = store.get('schools/s1/comprehensionEvals/old1');
    assert.equal(old1.transcript, undefined);
    assert.ok(old1.transcriptRemovedAt);
    assert.equal(old1.summary, 'ok');
    assert.equal(
      store.get('schools/s1/comprehensionEvals/fresh').transcript,
      'the dog found a bone');
    // Cursor sits at the newest cleaned doc; a re-run rescans nothing.
    const state = store.get(RETENTION_STATE_DOC);
    assert.ok(state.transcriptCursorEvaluatedAt.isEqual(ts(100)));
    const clearedAgain =
      await clearExpiredTranscripts(db, AI_EVAL_OPS_DEFAULTS, NOW);
    assert.equal(clearedAgain, 0);
  });

test('eval docs are deleted only after evalRetentionDays', async () => {
  const {db, store} = memDb({
    'schools/s1/comprehensionEvals/ancient': evalDoc(800),
    'schools/s1/comprehensionEvals/kept': evalDoc(400),
  });
  const deleted = await deleteExpiredEvals(db, AI_EVAL_OPS_DEFAULTS, NOW);
  assert.equal(deleted, 1);
  assert.equal(store.get('schools/s1/comprehensionEvals/ancient'), undefined);
  assert.ok(store.get('schools/s1/comprehensionEvals/kept'));
});

test('classification cache entries expire after ~12 months', async () => {
  const {db, store} = memDb({
    'aiQuestionClassifications/v1_aaa': {
      classifiedAt: new Date(NOW.getTime() - 400 * DAY_MS),
      categories: ['inference'],
    },
    'aiQuestionClassifications/v1_bbb': {
      classifiedAt: new Date(NOW.getTime() - 30 * DAY_MS),
      categories: ['open_retell'],
    },
  });
  const deleted = await deleteExpiredClassifications(db, NOW);
  assert.equal(deleted, 1);
  assert.equal(store.get('aiQuestionClassifications/v1_aaa'), undefined);
  assert.ok(store.get('aiQuestionClassifications/v1_bbb'));
});

test('runAiEvalRetention runs all three clocks', async () => {
  const {db} = memDb({
    'schools/s1/comprehensionEvals/old': evalDoc(120),
    'schools/s1/comprehensionEvals/ancient': evalDoc(800, {transcript: undefined}),
    'aiQuestionClassifications/v1_stale': {
      classifiedAt: new Date(NOW.getTime() - 400 * DAY_MS),
    },
  });
  const result = await runAiEvalRetention(db, AI_EVAL_OPS_DEFAULTS, NOW);
  assert.equal(result.transcriptsCleared, 1);
  assert.equal(result.evalsDeleted, 1);
  assert.equal(result.classificationsDeleted, 1);
});

test('audio deletion leaves the eval intact (documented behaviour)', () => {
  // deleteComprehensionAudio (comprehension_retention.ts) touches only the
  // audio object + audio fields on the reading log; nothing in that module
  // references comprehensionEvals. Guard against accidental coupling:
  const fs = require('node:fs');
  const path = require('node:path');
  const src = fs.readFileSync(
    path.resolve(__dirname, '../src/comprehension_retention.ts'), 'utf8');
  assert.ok(!src.includes('comprehensionEvals'));
});
