const { test } = require('node:test');
const assert = require('node:assert/strict');

const {
  defaultNotificationPermissions,
  normalizeNotificationPermissions,
  validateNotificationAudience,
  mergeRecipientsByParent,
  mergePushTargetsByToken,
  excludeAmbiguousPushTokenRecipients,
  isDueAt,
  isWithinQuietHours,
} = require('../lib/notification_helpers.js');

test('defaultNotificationPermissions returns whole-school access only for admins', () => {
  assert.deepEqual(defaultNotificationPermissions('teacher'), {
    assignedClasses: true,
    assignedStudents: true,
    schedule: true,
    wholeSchool: false,
  });

  assert.deepEqual(defaultNotificationPermissions('schoolAdmin'), {
    assignedClasses: true,
    assignedStudents: true,
    schedule: true,
    wholeSchool: true,
  });
});

test('normalizeNotificationPermissions merges stored overrides with role defaults', () => {
  assert.deepEqual(
    normalizeNotificationPermissions('teacher', {
      notifications: {
        assignedStudents: false,
      },
    }),
    {
      assignedClasses: true,
      assignedStudents: false,
      schedule: true,
      wholeSchool: false,
    },
  );
});

test('validateNotificationAudience allows assigned teacher classes and blocks whole-school', () => {
  assert.deepEqual(
    validateNotificationAudience({
      role: 'teacher',
      audienceType: 'classes',
      allowedClassIds: ['class_1'],
      targetClassIds: ['class_1'],
    }),
    { ok: true },
  );

  assert.equal(
    validateNotificationAudience({
      role: 'teacher',
      audienceType: 'school',
      allowedClassIds: ['class_1'],
    }).ok,
    false,
  );
});

test('validateNotificationAudience blocks students outside teacher assignments and allows admin school sends', () => {
  const blocked = validateNotificationAudience({
    role: 'teacher',
    audienceType: 'students',
    allowedClassIds: ['class_1'],
    studentClassIds: ['class_2'],
  });
  assert.equal(blocked.ok, false);

  const adminAllowed = validateNotificationAudience({
    role: 'schoolAdmin',
    audienceType: 'school',
    allowedClassIds: [],
  });
  assert.deepEqual(adminAllowed, { ok: true });
});

test('mergeRecipientsByParent deduplicates sibling recipients into one parent bucket', () => {
  const recipients = mergeRecipientsByParent([
    { id: 'student_1', firstName: 'Amy', classId: 'class_1', parentIds: ['parent_1'] },
    { id: 'student_2', firstName: 'Ben', classId: 'class_1', parentIds: ['parent_1', 'parent_2'] },
  ]);

  const parent1 = recipients.find((recipient) => recipient.parentId === 'parent_1');
  assert.ok(parent1);
  assert.deepEqual(parent1.studentIds.sort(), ['student_1', 'student_2']);

  const parent2 = recipients.find((recipient) => recipient.parentId === 'parent_2');
  assert.ok(parent2);
  assert.deepEqual(parent2.studentIds, ['student_2']);
});

test('mergePushTargetsByToken sends once per device and retains every parent owner', () => {
  assert.deepEqual(
    mergePushTargetsByToken([
      { parentId: 'parent_1', token: 'device_a' },
      { parentId: 'parent_2', token: 'device_a' },
      { parentId: 'parent_3', token: 'device_b' },
      { parentId: 'parent_4' },
      { parentId: 'parent_5', token: '  ' },
    ]),
    [
      { token: 'device_a', parentIds: ['parent_1', 'parent_2'] },
      { token: 'device_b', parentIds: ['parent_3'] },
    ],
  );
});

test('excludeAmbiguousPushTokenRecipients suppresses account-specific pushes to shared tokens', () => {
  const result = excludeAmbiguousPushTokenRecipients([
    { parentId: 'parent_1', token: 'device_a' },
    { parentId: 'parent_2', token: 'device_a' },
    { parentId: 'parent_3', token: 'device_b' },
  ]);

  assert.deepEqual(result.suppressedTokens, ['device_a']);
  assert.deepEqual(result.recipients, [
    { parentId: 'parent_3', token: 'device_b' },
  ]);
});

test('isDueAt only returns true once the scheduled time has passed', () => {
  assert.equal(isDueAt(null, Date.now()), true);
  assert.equal(isDueAt(Date.now() - 1000, Date.now()), true);
  assert.equal(isDueAt(Date.now() + 60_000, Date.now()), false);
});

test('isWithinQuietHours parses overnight quiet-hour windows correctly', () => {
  assert.equal(
    isWithinQuietHours(
      new Date('2026-03-19T10:00:00.000Z'),
      'UTC',
      { start: '19:00', end: '07:00' },
    ),
    false,
  );

  assert.equal(
    isWithinQuietHours(
      new Date('2026-03-19T22:30:00.000Z'),
      'UTC',
      { start: '19:00', end: '07:00' },
    ),
    true,
  );
});

// ── parseReminderHour ────────────────────────────────────────────────
// The denormalized reminderHour on parent docs must equal this function
// applied to preferences.reminderTime — these tests pin the contract,
// including the historical midnight quirk.

test('parseReminderHour: unset/empty/non-string default to 19', () => {
  const { parseReminderHour } = require('../lib/notification_helpers.js');
  assert.equal(parseReminderHour(undefined), 19);
  assert.equal(parseReminderHour(null), 19);
  assert.equal(parseReminderHour(''), 19);
  assert.equal(parseReminderHour(1830), 19);
});

test('parseReminderHour: parses the hour from HH:MM', () => {
  const { parseReminderHour } = require('../lib/notification_helpers.js');
  assert.equal(parseReminderHour('19:00'), 19);
  assert.equal(parseReminderHour('07:30'), 7);
  assert.equal(parseReminderHour('9:15'), 9);
  assert.equal(parseReminderHour('23:45'), 23);
});

test('parseReminderHour: midnight quirk — "00:xx" falls back to 19 (bug-for-bug with the old inline parse)', () => {
  const { parseReminderHour } = require('../lib/notification_helpers.js');
  assert.equal(parseReminderHour('00:30'), 19);
});

test('parseReminderHour: garbage strings fall back to 19', () => {
  const { parseReminderHour } = require('../lib/notification_helpers.js');
  assert.equal(parseReminderHour('bedtime'), 19);
});
