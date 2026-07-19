// Pure-helper tests for the local clip-review harness
// (scripts/ai-eval-clip-review.mjs): arg parsing, HTML escaping and the
// review-sheet rendering. Importing the script must run nothing — the
// harness only executes when invoked directly.
const test = require('node:test');
const assert = require('node:assert/strict');

// The harness is an ES module; load it once for all tests.
const harness = import('../scripts/ai-eval-clip-review.mjs');

test('parseArgs collects values and reports missing requireds', async () => {
  const {parseArgs} = await harness;
  const full = parseArgs([
    '--authorised', '--dir', '/clips', '--question', 'What happened?',
    '--out', '/tmp/sheet.html',
  ]);
  assert.deepEqual(full.errors, []);
  assert.equal(full.values.authorised, true);
  assert.equal(full.values.dir, '/clips');
  assert.equal(full.values.question, 'What happened?');
  assert.equal(full.values.out, '/tmp/sheet.html');

  const empty = parseArgs([]);
  assert.equal(empty.values.authorised, false);
  assert.ok(empty.errors.includes('--dir is required'));
  assert.ok(empty.errors.includes('--question is required'));
});

test('parseArgs rejects unknown flags and dangling values', async () => {
  const {parseArgs} = await harness;
  const unknown = parseArgs(['--dir', '/clips', '--question', 'Q', '--nope']);
  assert.ok(unknown.errors.some((e) => e.includes('unknown argument')));

  const dangling = parseArgs(['--dir', '--question']);
  assert.ok(dangling.errors.some((e) => e.includes('--dir requires a value')));
});

test('escapeHtml neutralises markup and quotes', async () => {
  const {escapeHtml} = await harness;
  assert.equal(
    escapeHtml('<script>"a" & \'b\'</script>'),
    '&lt;script&gt;&quot;a&quot; &amp; &#39;b&#39;&lt;/script&gt;');
  assert.equal(escapeHtml(undefined), '');
});

test('renderClipCard escapes content and always offers review boxes', async () => {
  const {renderClipCard} = await harness;
  const card = renderClipCard({
    fileName: 'clip one.m4a',
    transcript: 'the fox <b>ran</b>',
    sttConfidence: 0.91,
    billedSec: 7,
    lowConfidence: false,
    evaluation: {
      assessable: true,
      overallLevel: 'developing',
      confidence: 'medium',
      flags: ['incidental_personal_info'],
      summary: 'Recalled the <main> event.',
      criterionScores: [
        {criterionId: 'recall', score: 2, evidence: 'the fox <b>ran</b>'},
      ],
    },
  }, 0);
  assert.ok(card.includes('src="./clip%20one.m4a"'));
  assert.ok(card.includes('the fox &lt;b&gt;ran&lt;/b&gt;'));
  assert.ok(!card.includes('<b>ran</b>'));
  assert.ok(card.includes('incidental_personal_info'));
  assert.ok(card.includes('contenteditable="true"'));
  assert.ok(card.includes('Teacher notes'));
  assert.ok(card.includes('Accuracy verdict'));
});

test('renderClipCard renders error and inaudible states without eval', async () => {
  const {renderClipCard} = await harness;
  const errored = renderClipCard({fileName: 'x.m4a', error: 'stt_http_429'}, 1);
  assert.ok(errored.includes('stt_http_429'));
  assert.ok(!errored.includes('Transcript'));

  const inaudible = renderClipCard({
    fileName: 'y.m4a', inaudible: true, sttConfidence: 1, billedSec: 2,
  }, 2);
  assert.ok(inaudible.includes('inaudible'));
  assert.ok(!inaudible.includes('Evaluation<'));
});

test('buildReviewSheetHtml is one self-contained document', async () => {
  const {buildReviewSheetHtml} = await harness;
  const html = buildReviewSheetHtml({
    generatedAt: '2026-07-20T00:00:00Z',
    model: 'gemini-2.5-flash',
    question: 'What happened in the "story"?',
    rubricKey: 'general',
    rubricVersion: 1,
    clipCount: 1,
  }, [{fileName: 'a.m4a', inaudible: true, sttConfidence: 1, billedSec: 1}]);
  assert.ok(html.startsWith('<!doctype html>'));
  assert.ok(html.includes('gemini-2.5-flash'));
  assert.ok(html.includes('What happened in the &quot;story&quot;?'));
  assert.ok(html.includes('a.m4a'));
  assert.ok(html.includes('nothing was written to Firestore'));
  // Self-contained: no external scripts or stylesheets.
  assert.ok(!html.includes('<script'));
  assert.ok(!html.includes('<link'));
});

test('importing the harness does not run main', async () => {
  // If import executed main(), the missing --authorised flag would have
  // called process.exit(2) before any test ran; reaching here plus an
  // exported warning constant is the regression guard.
  const {AUTHORISATION_WARNING} = await harness;
  assert.ok(AUTHORISATION_WARNING.includes('--authorised'));
});
