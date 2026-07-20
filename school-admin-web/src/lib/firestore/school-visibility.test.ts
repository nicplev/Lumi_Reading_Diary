import assert from 'node:assert/strict';
import test from 'node:test';

import {
  ADMIN_ONLY_SCHOOL_FIELDS,
  stripAdminOnlySchoolFields,
} from './school-visibility.ts';

// Fixture carries every admin-only field (so the teacher-strip test proves
// each is actively removed) plus the branding/config teachers must keep.
const fullSchool = (): Record<string, unknown> => {
  const base: Record<string, unknown> = {
    id: 'school1',
    name: 'Test School',
    displayName: 'Test',
    logoUrl: 'https://x/y.png',
    primaryColor: '#111',
    secondaryColor: '#222',
    settings: { comprehensionRecording: { enabled: true } },
    termDates: { term1Start: '2026-01-28' },
  };
  for (const key of ADMIN_ONLY_SCHOOL_FIELDS) base[key] = `admin-${key}`;
  return base;
};

test('schoolAdmin gets the full payload unchanged', () => {
  const payload = fullSchool();
  const out = stripAdminOnlySchoolFields(payload, 'schoolAdmin');
  assert.equal(out, payload); // same reference — no copy for admins
  for (const key of ADMIN_ONLY_SCHOOL_FIELDS) {
    assert.ok(key in out, `admin keeps ${key}`);
  }
});

test('teacher payload keeps branding/config but drops commercial+contact fields', () => {
  const out = stripAdminOnlySchoolFields(fullSchool(), 'teacher');
  // Kept — teacher UI needs these.
  for (const key of ['name', 'displayName', 'logoUrl', 'primaryColor', 'secondaryColor', 'settings', 'termDates']) {
    assert.ok(key in out, `teacher keeps ${key}`);
  }
  // Stripped — commercial/contact.
  for (const key of ADMIN_ONLY_SCHOOL_FIELDS) {
    assert.ok(!(key in out), `teacher must not receive ${key}`);
  }
});

test('stripping does not mutate the input payload', () => {
  const payload = fullSchool();
  stripAdminOnlySchoolFields(payload, 'teacher');
  assert.ok('subscription' in payload, 'original payload is untouched');
});
