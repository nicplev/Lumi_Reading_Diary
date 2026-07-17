const {test} = require('node:test');
const assert = require('node:assert/strict');
const {Timestamp} = require('firebase-admin/firestore');

const {
  CLASS_DAILY_READING_SHARDS,
  applyDailyReadingDelta,
  buildDailyReadingProjection,
  dailyReadingShard,
} = require('../lib/class_daily_reading.js');

const projection = (overrides = {}) => ({
  classId: 'class_1',
  localDate: '2026-07-17',
  shard: dailyReadingShard('student_1'),
  studentId: 'student_1',
  minutes: 20,
  teacherLogs: 0,
  ...overrides,
});

test('student sharding is deterministic and remains within bounds', () => {
  const first = dailyReadingShard('student_1');
  assert.equal(dailyReadingShard('student_1'), first);
  assert.ok(first >= 0 && first < CLASS_DAILY_READING_SHARDS);
});

test('projection counts only valid completed/partial logs in school local time', () => {
  const source = {
    classId: 'class_1',
    studentId: 'student_1',
    date: Timestamp.fromDate(new Date('2026-07-16T14:30:00.000Z')),
    minutesRead: 20,
    status: 'completed',
    loggedByRole: 'teacher',
  };
  const result = buildDailyReadingProjection(source, 'Australia/Melbourne');
  assert.equal(result.localDate, '2026-07-17');
  assert.equal(result.teacherLogs, 1);
  assert.equal(
    buildDailyReadingProjection({...source, validationStatus: 'invalid'}, 'UTC'),
    null,
  );
  assert.equal(
    buildDailyReadingProjection({...source, status: 'pending'}, 'UTC'),
    null,
  );
});

test('daily deltas preserve exact unique-student and minute counts', () => {
  const first = projection();
  const afterFirst = applyDailyReadingDelta(undefined, first, null, first);
  assert.equal(afterFirst.logCount, 1);
  assert.equal(afterFirst.activeStudentCount, 1);
  assert.equal(afterFirst.totalMinutes, 20);

  const second = projection({minutes: 15, teacherLogs: 1});
  const afterSecond = applyDailyReadingDelta(afterFirst, second, null, second);
  assert.equal(afterSecond.logCount, 2);
  assert.equal(afterSecond.activeStudentCount, 1);
  assert.equal(afterSecond.totalMinutes, 35);
  assert.equal(afterSecond.teacherLogCount, 1);

  const afterDelete = applyDailyReadingDelta(afterSecond, first, first, null);
  assert.equal(afterDelete.logCount, 1);
  assert.equal(afterDelete.activeStudentCount, 1);
  assert.equal(afterDelete.totalMinutes, 15);
});

test('removing the last projection deletes the empty bucket', () => {
  const item = projection();
  const populated = applyDailyReadingDelta(undefined, item, null, item);
  assert.equal(applyDailyReadingDelta(populated, item, item, null), null);
});
