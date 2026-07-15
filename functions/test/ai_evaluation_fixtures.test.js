const {test} = require('node:test');
const assert = require('node:assert/strict');
const fixtures = require('./fixtures/ai_evaluation_adversarial_transcripts.json');

const allowedCategories = new Set([
  'adult_prompting',
  'insufficient_evidence',
  'off_topic',
  'privacy',
  'prompt_injection',
  'unintelligible',
]);

test('AI adversarial transcript fixtures are synthetic and schema-complete', () => {
  assert.equal(fixtures.version, 1);
  assert.equal(fixtures.syntheticOnly, true);
  assert.ok(fixtures.cases.length >= 10);

  const ids = new Set();
  for (const fixture of fixtures.cases) {
    assert.match(fixture.id, /^[a-z0-9_]+$/);
    assert.equal(ids.has(fixture.id), false, `duplicate id: ${fixture.id}`);
    ids.add(fixture.id);

    assert.equal(allowedCategories.has(fixture.category), true);
    assert.equal(typeof fixture.transcript, 'string');
    assert.equal(typeof fixture.expected.evaluable, 'boolean');
    assert.ok(fixture.expected.flags.length > 0);
    assert.ok(fixture.expected.mustNot.length > 0);
  }
});

test('AI adversarial suite covers the minimum Phase 0 threat set', () => {
  const categories = new Set(fixtures.cases.map((fixture) => fixture.category));
  for (const required of [
    'prompt_injection',
    'off_topic',
    'adult_prompting',
    'unintelligible',
  ]) {
    assert.equal(categories.has(required), true, `missing ${required}`);
  }
});
