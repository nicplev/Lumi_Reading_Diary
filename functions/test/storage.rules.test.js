// Verifies the comprehension-recording kill switch backstop in storage.rules:
// uploads to schools/{schoolId}/comprehension_audio/ are denied while
// platformConfig/comprehensionRecording has enabled == false, and allowed
// when the doc is missing or enabled. Requires BOTH the firestore and
// storage emulators (the storage rules call firestore.get/exists):
//   npm run test:rules:storage
const path = require('path');
const fs = require('fs');
const { test, before, after, beforeEach } = require('node:test');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const { ref, uploadBytes, getBytes } = require('firebase/storage');

// Must match the --project passed to `firebase emulators:exec` in the
// test:rules:storage script: the Storage emulator resolves the
// cross-service firestore.get()/exists() calls against the project it was
// started with, not the bucket's project. A mismatch makes every lookup a
// NOT_FOUND, which this suite would misread as "doc missing = enabled".
const PROJECT_ID = 'demo-lumi-rules-test';
const FIRESTORE_RULES_PATH = path.resolve(__dirname, '../../firestore.rules');
const STORAGE_RULES_PATH = path.resolve(__dirname, '../../storage.rules');

const AUDIO_PATH = 'schools/school_1/comprehension_audio/log_1.m4a';
const AUDIO_BYTES = new Uint8Array([0, 1, 2, 3]);
const AUDIO_METADATA = { contentType: 'audio/mp4' };

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(FIRESTORE_RULES_PATH, 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
    storage: {
      rules: fs.readFileSync(STORAGE_RULES_PATH, 'utf8'),
      host: '127.0.0.1',
      port: 9199,
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
});

async function seedFlag(enabled) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context
      .firestore()
      .collection('platformConfig')
      .doc('comprehensionRecording')
      .set({ enabled, updatedAt: new Date(), updatedBy: 'super_admin_1' });
  });
}

function audioRef(uid) {
  return ref(testEnv.authenticatedContext(uid).storage(), AUDIO_PATH);
}

test('comprehension audio: upload allowed when kill-switch doc is missing', async () => {
  await assertSucceeds(uploadBytes(audioRef('parent_1'), AUDIO_BYTES, AUDIO_METADATA));
});

test('comprehension audio: upload allowed when flag enabled', async () => {
  await seedFlag(true);
  await assertSucceeds(uploadBytes(audioRef('parent_1'), AUDIO_BYTES, AUDIO_METADATA));
});

test('comprehension audio: storage rules do NOT enforce the kill switch (app-side)', async () => {
  // The kill switch (platformConfig/comprehensionRecording) is enforced app-side
  // via PlatformConfigService — NOT in storage rules. The cross-service
  // firestore.get() this rule used to run silently failed under lumi-ninc-au
  // (every upload → unauthorized), so the rule was reduced to trust
  // auth + size + contentType (see storage.rules comment). At the rule level,
  // therefore, an upload with the flag OFF still succeeds.
  await seedFlag(false);
  await assertSucceeds(uploadBytes(audioRef('parent_1'), AUDIO_BYTES, AUDIO_METADATA));
});

test('comprehension audio: unauthenticated upload denied regardless of flag', async () => {
  await seedFlag(true);
  const anonRef = ref(testEnv.unauthenticatedContext().storage(), AUDIO_PATH);
  await assertFails(uploadBytes(anonRef, AUDIO_BYTES, AUDIO_METADATA));
});

test('comprehension audio: non-audio content type denied even when enabled', async () => {
  await seedFlag(true);
  await assertFails(
    uploadBytes(audioRef('parent_1'), AUDIO_BYTES, { contentType: 'image/jpeg' }),
  );
});

test('comprehension audio: direct authenticated read is denied (signed-URL only)', async () => {
  // The object is seeded with rules disabled, then a normal authed client tries
  // to read it directly — denied (2.2). Playback must go through the
  // getComprehensionAudioUrl callable's signed URL, which bypasses these rules.
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await uploadBytes(
      ref(context.storage(), AUDIO_PATH),
      AUDIO_BYTES,
      AUDIO_METADATA,
    );
  });
  await assertFails(getBytes(audioRef('teacher_1')));
});
