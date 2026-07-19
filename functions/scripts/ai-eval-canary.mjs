#!/usr/bin/env node
// Production E2E canary for the AI comprehension-evaluation pipeline.
//
// SYNTHETIC CONTENT ONLY — the audio is macOS `say` speech, never a child.
// Creates a throwaway canary school, drives the real deployed worker, and
// removes EVERY artifact in a finally block. Two phases:
//
//   Phase A (negative, zero provider spend): kill switch OFF + entitled
//     canary school -> job created -> worker must terminate done/disabled
//     with NO eval doc. Proves the fail-closed claim-time gate in prod.
//   Phase B (positive): kill switch ON briefly -> job -> full pipeline
//     (STT + Gemini, both Sydney) -> eval doc written -> switch OFF.
//
// Safe because zero real schools are entitled: with the platform switch on,
// nothing but this canary can enqueue.

import admin from 'firebase-admin';
import fs from 'node:fs';

const PROJECT = 'lumi-ninc-au';
const SCHOOL = 'zz_canary_ai_eval';
const CLASS = 'zz_canary_class';
const STUDENT = 'zz_canary_student';
const LOG = 'zz_canary_log';
const JOB = `${SCHOOL}_${LOG}`;
const AUDIO = process.argv[2];
if (!AUDIO || !fs.existsSync(AUDIO)) {
  console.error('usage: node ai-eval-canary.mjs <synthetic.m4a>');
  process.exit(2);
}

admin.initializeApp({
  projectId: PROJECT,
  storageBucket: `${PROJECT}.firebasestorage.app`,
});
const db = admin.firestore();
const bucket = admin.storage().bucket();
const FLAG = db.doc('platformConfig/aiEvaluation');
const AUDIO_PATH = `schools/${SCHOOL}/comprehension_audio/${LOG}.m4a`;
const VALIDATION_VERSION = 'ffmpeg-aac-mono-v1';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (...a) => console.log(...a);

async function waitForJob(predicate, timeoutMs, label) {
  const started = Date.now();
  let last = null;
  while (Date.now() - started < timeoutMs) {
    const snap = await db.doc(`aiEvalJobs/${JOB}`).get();
    last = snap.exists ? snap.data() : null;
    if (last && predicate(last)) return last;
    await sleep(3000);
  }
  throw new Error(
    `timeout waiting for ${label}; last job state=${JSON.stringify(last)}`
  );
}

async function seedFixture() {
  await db.doc(`schools/${SCHOOL}`).set({
    name: 'ZZ Canary (AI eval E2E)',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    isActive: false,
    timezone: 'Australia/Sydney',
    settings: { aiEvaluation: { enabled: true, termsVersionAccepted: 'canary' } },
  });
  await db.doc(`schools/${SCHOOL}/adminMeta/aiEvaluation`).set({
    capPerDay: 5, plan: 'canary', notes: 'automated E2E canary',
  });
  await db.doc(`schools/${SCHOOL}/classes/${CLASS}`).set({
    schoolId: SCHOOL, name: 'Canary Class', teacherIds: [],
    settings: { comprehensionQuestion: 'What happened at the start of the story?' },
  });
  await db.doc(`schools/${SCHOOL}/students/${STUDENT}`).set({
    schoolId: SCHOOL, classId: CLASS, firstName: 'Canary', lastName: 'Student',
    name: 'Canary Student', isActive: false,
  });

  const [file] = await bucket.upload(AUDIO, {
    destination: AUDIO_PATH,
    metadata: { contentType: 'audio/mp4' },
  });
  const [meta] = await file.getMetadata();
  const generation = String(meta.generation);
  log(`  audio uploaded, generation=${generation}`);

  await db.doc(`schools/${SCHOOL}/readingLogs/${LOG}`).set({
    schoolId: SCHOOL, studentId: STUDENT, classId: CLASS,
    parentId: 'zz_canary_parent', loggedByRole: 'parent',
    date: admin.firestore.Timestamp.now(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    minutesRead: 15,
    comprehensionAudioPath: AUDIO_PATH,
    comprehensionAudioDurationSec: 12,
    comprehensionAudioUploaded: true,
    comprehensionAudioUploadedAt: admin.firestore.FieldValue.serverTimestamp(),
    comprehensionAudioObjectGeneration: generation,
    comprehensionAudioValidationVersion: VALIDATION_VERSION,
    comprehensionQuestionText: 'What happened at the start of the story?',
    comprehensionQuestionCapturedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return generation;
}

async function createJob(generation) {
  await db.doc(`aiEvalJobs/${JOB}`).delete().catch(() => {});
  const logSnap = await db.doc(`schools/${SCHOOL}/readingLogs/${LOG}`).get();
  await db.doc(`aiEvalJobs/${JOB}`).create({
    schoolId: SCHOOL, logId: LOG, studentId: STUDENT, classId: CLASS,
    status: 'queued', attempts: 0,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    sourceUploadedAt: logSnap.data().comprehensionAudioUploadedAt,
    audioObjectGeneration: generation,
    audioValidationVersion: VALIDATION_VERSION,
  });
}

async function cleanup() {
  log('\n[cleanup] restoring kill switch + removing all canary data');
  await FLAG.set({ enabled: false }, { merge: true });
  const flagAfter = (await FLAG.get()).data();
  log(`  kill switch enabled=${flagAfter?.enabled}`);
  await db.doc(`aiEvalJobs/${JOB}`).delete().catch(() => {});
  await db.recursiveDelete(db.doc(`schools/${SCHOOL}`));
  await bucket.file(AUDIO_PATH).delete({ ignoreNotFound: true });
  // Canary spend counted against the shared global shard counters; leave
  // those (they are date-scoped and roll over) but clear school budget docs
  // via the recursive school delete above.
  const residue = {
    job: (await db.doc(`aiEvalJobs/${JOB}`).get()).exists,
    school: (await db.doc(`schools/${SCHOOL}`).get()).exists,
    evalDoc: (await db.doc(`schools/${SCHOOL}/comprehensionEvals/${LOG}`).get()).exists,
    audio: (await bucket.file(AUDIO_PATH).exists())[0],
  };
  log(`  residue check: ${JSON.stringify(residue)}`);
  if (Object.values(residue).some(Boolean)) {
    throw new Error(`CANARY RESIDUE LEFT BEHIND: ${JSON.stringify(residue)}`);
  }
  log('  ✓ zero residue');
}

const results = {};
try {
  const before = (await FLAG.get()).data();
  log(`[pre] kill switch enabled=${before?.enabled}`);
  if (before?.enabled === true) throw new Error('switch already ON — abort');

  log('\n[phase A] negative test — switch OFF, entitled school');
  const generation = await seedFixture();
  await createJob(generation);
  const a = await waitForJob(
    (j) => j.status === 'done' || j.status === 'poisoned' || j.status === 'failed',
    90_000, 'phase A terminal'
  );
  const evalAfterA = await db.doc(`schools/${SCHOOL}/comprehensionEvals/${LOG}`).get();
  results.phaseA = {
    status: a.status, doneReason: a.doneReason ?? null,
    evalDocCreated: evalAfterA.exists,
  };
  log(`  job -> status=${a.status} doneReason=${a.doneReason} evalDoc=${evalAfterA.exists}`);
  if (a.status !== 'done' || a.doneReason !== 'disabled' || evalAfterA.exists) {
    throw new Error(`phase A FAILED: ${JSON.stringify(results.phaseA)}`);
  }
  log('  ✓ fail-closed gate held: terminated disabled, no eval, no spend');

  log('\n[phase B] positive test — switch ON briefly');
  await FLAG.set({ enabled: true, updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedBy: 'system:e2e-canary', reason: 'automated canary' }, { merge: true });
  log('  kill switch ON');
  await createJob(generation);
  const b = await waitForJob(
    (j) => ['done', 'failed', 'poisoned', 'deferred'].includes(j.status),
    240_000, 'phase B terminal'
  );
  const evalSnap = await db.doc(`schools/${SCHOOL}/comprehensionEvals/${LOG}`).get();
  const e = evalSnap.exists ? evalSnap.data() : null;
  results.phaseB = {
    jobStatus: b.status, deferredReason: b.deferredReason ?? null,
    lastError: b.lastError ?? null,
    evalDocCreated: evalSnap.exists,
    evalStatus: e?.status ?? null,
    overallLevel: e?.overallLevel ?? null,
    confidence: e?.confidence ?? null,
    assessable: e?.assessable ?? null,
    flags: e?.flags ?? null,
    transcript: e?.transcript ?? null,
    sttConfidence: e?.sttConfidence ?? null,
    summary: e?.summary ?? null,
    criterionScores: e?.criterionScores ?? null,
    model: e?.model ?? null,
    questionSource: e?.questionSource ?? null,
    usage: e?.usage ?? null,
  };
  log(`  job -> ${b.status}; eval -> ${e?.status} level=${e?.overallLevel}`);
  log(`  transcript: ${JSON.stringify(e?.transcript)}`);
  log(`  summary: ${JSON.stringify(e?.summary)}`);
} catch (err) {
  results.error = String(err?.message ?? err);
  console.error('\n[ERROR]', results.error);
} finally {
  try {
    await cleanup();
    results.cleanup = 'ok';
  } catch (err) {
    results.cleanup = `FAILED: ${err?.message ?? err}`;
    console.error('[cleanup ERROR]', results.cleanup);
  }
  console.log('\n=== CANARY RESULTS ===');
  console.log(JSON.stringify(results, null, 1));
  process.exit(results.error || results.cleanup !== 'ok' ? 1 : 0);
}
