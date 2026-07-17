const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const admin = require('firebase-admin');

const {
  accountDeletionJobId,
  studentDeletionJobId,
  publicDeletionStatus,
  isDeletionJobDue,
} = require('../lib/deletion');

const timestamp = (millis) => admin.firestore.Timestamp.fromMillis(millis);

test('deletion job ids are deterministic without exposing raw identifiers', () => {
  const account = accountDeletionJobId('uid-sensitive');
  assert.equal(account, accountDeletionJobId('uid-sensitive'));
  assert.notEqual(account, accountDeletionJobId('different-user'));
  assert.match(account, /^account_[a-f0-9]{64}$/);
  assert.equal(account.includes('uid-sensitive'), false);

  const student = studentDeletionJobId('school-a', 'student-sensitive');
  assert.equal(student, studentDeletionJobId('school-a', 'student-sensitive'));
  assert.notEqual(student, studentDeletionJobId('school-b', 'student-sensitive'));
  assert.match(student, /^student_[a-f0-9]{64}$/);
  assert.equal(student.includes('student-sensitive'), false);
});

test('public status omits identifiers, counts and internal failure details', () => {
  const status = publicDeletionStatus('account_hash', {
    kind: 'account',
    status: 'failed',
    requesterUid: 'secret-user',
    requesterHash: 'secret-hash',
    studentId: 'secret-student',
    requestedAt: timestamp(1000),
    attemptCount: 2,
    counts: { deleted: 99 },
    errorCode: 'internal-secret',
  });

  assert.deepEqual(Object.keys(status).sort(), [
    'attemptCount',
    'completedAt',
    'jobId',
    'kind',
    'requestedAt',
    'retrying',
    'scheduledDeletionAt',
    'startedAt',
    'status',
  ]);
  assert.equal(JSON.stringify(status).includes('secret'), false);
  assert.equal(status.retrying, true);
  assert.equal(status.requestedAt, '1970-01-01T00:00:01.000Z');
});

test('due-state logic handles schedules, retries, leases and terminal states', () => {
  const now = 10_000;
  const base = { kind: 'account', requesterHash: 'hash' };

  assert.equal(isDeletionJobDue({ ...base, status: 'pending', scheduledDeletionAt: timestamp(now) }, now), true);
  assert.equal(isDeletionJobDue({ ...base, status: 'pending', scheduledDeletionAt: timestamp(now + 1) }, now), false);
  assert.equal(isDeletionJobDue({ ...base, status: 'failed', nextAttemptAt: timestamp(now - 1), attemptCount: 2 }, now), true);
  assert.equal(isDeletionJobDue({ ...base, status: 'processing', leaseExpiresAt: timestamp(now - 1), attemptCount: 2 }, now), true);
  assert.equal(isDeletionJobDue({ ...base, status: 'processing', leaseExpiresAt: timestamp(now + 1), attemptCount: 2 }, now), false);
  assert.equal(isDeletionJobDue({ ...base, status: 'completed' }, now), false);
  assert.equal(isDeletionJobDue({ ...base, status: 'failed', nextAttemptAt: timestamp(now - 1), attemptCount: 5 }, now), false);
});

test('production indexes support cross-school student notification cleanup', () => {
  const config = JSON.parse(fs.readFileSync(
    path.resolve(__dirname, '..', '..', 'firestore.indexes.json'),
    'utf8',
  ));
  const override = config.fieldOverrides.find((entry) =>
    entry.collectionGroup === 'notifications' &&
    entry.fieldPath === 'studentIds'
  );

  assert.ok(override, 'notifications.studentIds field override is required');
  assert.ok(override.indexes.some((index) =>
    index.order === 'ASCENDING' &&
    index.queryScope === 'COLLECTION'
  ));
  assert.ok(override.indexes.some((index) =>
    index.order === 'DESCENDING' &&
    index.queryScope === 'COLLECTION'
  ));
  assert.ok(override.indexes.some((index) =>
    index.arrayConfig === 'CONTAINS' &&
    index.queryScope === 'COLLECTION'
  ));
  assert.ok(override.indexes.some((index) =>
    index.arrayConfig === 'CONTAINS' &&
    index.queryScope === 'COLLECTION_GROUP'
  ));
});

test('production indexes support cross-school account content cleanup', () => {
  const config = JSON.parse(fs.readFileSync(
    path.resolve(__dirname, '..', '..', 'firestore.indexes.json'),
    'utf8',
  ));

  for (const [collectionGroup, fieldPath] of [
    ['comments', 'authorId'],
    ['deletionRequests', 'requestedBy'],
  ]) {
    const override = config.fieldOverrides.find((entry) =>
      entry.collectionGroup === collectionGroup &&
      entry.fieldPath === fieldPath
    );
    assert.ok(override, `${collectionGroup}.${fieldPath} override is required`);
    assert.ok(override.indexes.some((index) =>
      index.order === 'ASCENDING' && index.queryScope === 'COLLECTION'
    ));
    assert.ok(override.indexes.some((index) =>
      index.order === 'DESCENDING' && index.queryScope === 'COLLECTION'
    ));
    assert.ok(override.indexes.some((index) =>
      index.arrayConfig === 'CONTAINS' &&
      index.queryScope === 'COLLECTION'
    ));
    assert.ok(override.indexes.some((index) =>
      index.order === 'ASCENDING' &&
      index.queryScope === 'COLLECTION_GROUP'
    ));
  }
});

test('checked-in index config preserves live rate-limit TTL policies', () => {
  const config = JSON.parse(fs.readFileSync(
    path.resolve(__dirname, '..', '..', 'firestore.indexes.json'),
    'utf8',
  ));

  for (const collectionGroup of [
    'publicCodeVerificationRateLimits',
    'schoolCodeRedemptions',
  ]) {
    const override = config.fieldOverrides.find((entry) =>
      entry.collectionGroup === collectionGroup &&
      entry.fieldPath === 'expiresAt'
    );
    assert.ok(override, `${collectionGroup}.expiresAt override is required`);
    assert.equal(override.ttl, true);
    assert.ok(override.indexes.some((index) =>
      index.order === 'ASCENDING' && index.queryScope === 'COLLECTION'
    ));
    assert.ok(override.indexes.some((index) =>
      index.order === 'DESCENDING' && index.queryScope === 'COLLECTION'
    ));
    assert.ok(override.indexes.some((index) =>
      index.arrayConfig === 'CONTAINS' &&
      index.queryScope === 'COLLECTION'
    ));
  }
});
