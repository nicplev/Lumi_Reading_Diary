const { test } = require('node:test');
const assert = require('node:assert/strict');

const { renderSchoolNoteBlock } = require('../lib/email_templates.js');

test('renderSchoolNoteBlock returns empty for no message', () => {
  assert.equal(renderSchoolNoteBlock(undefined), '');
  assert.equal(renderSchoolNoteBlock(''), '');
});

test('renderSchoolNoteBlock escapes admin-supplied HTML (no injection)', () => {
  const html = renderSchoolNoteBlock(
    '<a href="https://evil.example">Reset your account</a><img src=x onerror=alert(1)>',
  );
  // The raw markup must not survive into the email body.
  assert.ok(!html.includes('<a href="https://evil.example">'));
  assert.ok(!html.includes('<img src=x'));
  // It is present as escaped text instead.
  assert.ok(html.includes('&lt;a href=&quot;https://evil.example&quot;&gt;'));
  assert.ok(html.includes('&lt;img src=x'));
});

test('renderSchoolNoteBlock converts newlines to <br/> after escaping', () => {
  const html = renderSchoolNoteBlock('line one\nline two');
  assert.ok(html.includes('line one<br/>line two'));
});

test('renderSchoolNoteBlock keeps the note chrome for a plain message', () => {
  const html = renderSchoolNoteBlock('Welcome to reading!');
  assert.ok(html.includes('A note from your school'));
  assert.ok(html.includes('Welcome to reading!'));
});
