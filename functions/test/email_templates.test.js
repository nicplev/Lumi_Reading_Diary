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

// ─── Roster-supplied values (student/staff names, school name) ──────────
// These reach the templates from the school roster — including bulk SIS/CSV
// imports, where an attacker-supplied file can smuggle markup into a name.
// The onboarding emails go to parents from the school's trusted sender, so
// unescaped markup here would be a ready-made phishing surface.

const {
  renderEntryCard,
  buildOnboardingEmail,
  buildStaffOnboardingEmail,
} = require('../lib/email_templates.js');

const NAME_PAYLOAD =
  '<a href="https://evil.example">Click to verify</a><img src=x onerror=alert(1)>';

test('renderEntryCard escapes an imported student name', () => {
  const html = renderEntryCard({
    studentName: NAME_PAYLOAD,
    linkCode: 'ABC123',
    qrSrc: 'cid:qr',
  });
  assert.ok(!html.includes('<a href="https://evil.example">'));
  assert.ok(!html.includes('<img src=x'));
  assert.ok(html.includes('&lt;a href=&quot;https://evil.example&quot;&gt;'));
  // The legitimate content still renders.
  assert.ok(html.includes('ABC123'));
});

test('buildOnboardingEmail escapes student and school names end to end', () => {
  const html = buildOnboardingEmail({
    schoolName: '<script>alert(1)</script>Evil School',
    entries: [{ studentName: NAME_PAYLOAD, linkCode: 'ABC123' }],
  });
  assert.ok(!html.includes('<script>alert(1)</script>'));
  assert.ok(!html.includes('<a href="https://evil.example">'));
  assert.ok(!html.includes('<img src=x'));
  assert.ok(html.includes('&lt;script&gt;'));
});

test('buildStaffOnboardingEmail escapes name, school and login email', () => {
  const html = buildStaffOnboardingEmail({
    schoolName: '<script>alert(1)</script>School',
    staffName: NAME_PAYLOAD,
    role: 'teacher',
    loginEmail: '<img src=x onerror=alert(2)>@example.com',
    tempPassword: 'Temp-Passw0rd!',
    portalUrl: 'https://portal.example',
  });
  assert.ok(!html.includes('<script>alert(1)</script>'));
  assert.ok(!html.includes('<a href="https://evil.example">'));
  assert.ok(!html.includes('<img src=x'));
  // The real credential still reaches the recipient.
  assert.ok(html.includes('Temp-Passw0rd!'));
});

test('ordinary names are unchanged by escaping', () => {
  const html = renderEntryCard({
    studentName: "Ada O'Brien-Nguyen",
    linkCode: 'ABC123',
    qrSrc: 'cid:qr',
  });
  // Apostrophe is entity-encoded but renders identically in a mail client.
  assert.ok(html.includes('Ada O&#39;Brien-Nguyen'));
});
