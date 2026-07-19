// Unit tests for the Phase 7 report aggregation core.
const test = require('node:test');
const assert = require('node:assert/strict');

const {
  buildStudentEvalAggregates,
  buildNarrativePrompt,
  MIN_ASSESSABLE_FOR_REPORT,
} = require('../lib/ai_evaluation/report.js');

function evalItem(overrides = {}) {
  return {
    logDate: new Date('2026-07-15T00:00:00Z'),
    status: 'complete',
    overallLevel: 'developing',
    assessable: true,
    flags: [],
    summary: 'The student recalled the main events with supporting detail.',
    questionCategories: ['literal_recall'],
    criterionScores: [
      {criterionId: 'recall', score: 2},
      {criterionId: 'detail', score: 1},
    ],
    promptVersion: 1,
    rubricVersion: 1,
    model: 'gemini-2.5-flash',
    ...overrides,
  };
}

test('aggregates: counts, levels, categories, quotes', () => {
  const aggregates = buildStudentEvalAggregates([
    evalItem(),
    evalItem({overallLevel: 'secure',
      criterionScores: [{criterionId: 'recall', score: 3}]}),
    evalItem({overallLevel: 'developing'}),
    evalItem({assessable: false, overallLevel: null,
      flags: ['inaudible'], summary: null}),
  ]);
  assert.equal(aggregates.evaluatedCount, 4);
  assert.equal(aggregates.assessableCount, 3);
  assert.equal(aggregates.flaggedCount, 1);
  assert.equal(aggregates.levelCounts.developing, 2);
  assert.equal(aggregates.levelCounts.secure, 1);
  assert.equal(aggregates.flagCounts.inaudible, 1);
  // literal_recall has 3 assessable data points -> average present.
  assert.ok(aggregates.categoryAverages.literal_recall);
  assert.equal(aggregates.categoryAverages.literal_recall.count, 3);
  assert.ok(aggregates.quotes.length >= 1 && aggregates.quotes.length <= 3);
  assert.equal(aggregates.insufficientData, false);
});

test('aggregates: category averages need >= 2 data points', () => {
  const aggregates = buildStudentEvalAggregates([
    evalItem({questionCategories: ['inference']}),
    evalItem({questionCategories: ['literal_recall']}),
    evalItem({questionCategories: ['literal_recall']}),
  ]);
  assert.ok(aggregates.categoryAverages.literal_recall);
  assert.equal(aggregates.categoryAverages.inference, undefined);
});

test('aggregates: sparse data marks insufficient', () => {
  const aggregates = buildStudentEvalAggregates([
    evalItem(), evalItem({assessable: false, overallLevel: null}),
  ]);
  assert.equal(aggregates.assessableCount, 1);
  assert.ok(aggregates.assessableCount < MIN_ASSESSABLE_FOR_REPORT);
  assert.equal(aggregates.insufficientData, true);
});

test('aggregates: trend segments split at version/model boundaries', () => {
  const aggregates = buildStudentEvalAggregates([
    evalItem({logDate: new Date('2026-07-06T00:00:00Z')}),
    evalItem({logDate: new Date('2026-07-13T00:00:00Z')}),
    evalItem({
      logDate: new Date('2026-07-14T00:00:00Z'),
      promptVersion: 2,
    }),
    evalItem({
      logDate: new Date('2026-07-15T00:00:00Z'),
      model: 'gemini-3.1-flash-lite',
    }),
  ]);
  assert.equal(aggregates.segments.length, 3);
  const weeks = aggregates.segments[0].weeks.map((w) => w.weekStart);
  assert.deepEqual(weeks, ['2026-07-06', '2026-07-13']);
});

test('narrative prompt is aggregates-only and name-free', () => {
  const aggregates = buildStudentEvalAggregates([
    evalItem(), evalItem(), evalItem(),
  ]);
  const prompt = buildNarrativePrompt(aggregates, 'Term 3 2026');
  assert.ok(prompt.includes('"the student"'));
  assert.ok(prompt.includes('Term 3 2026'));
  // The prompt must never carry transcripts or quotes (only counts).
  assert.ok(!prompt.includes('recalled the main events'));
});
