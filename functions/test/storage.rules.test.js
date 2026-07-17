// Verifies owner/class metadata and feature-gate enforcement in storage.rules.
// Requires BOTH emulators because Storage rules authorize against Firestore:
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

const AUDIO_PATH = 'comprehension_audio_uploads/school_1/log_1.m4a';
const CANONICAL_AUDIO_PATH = 'schools/school_1/comprehension_audio/log_1.m4a';
const AUDIO_BYTES = new Uint8Array([0, 1, 2, 3]);
const AUDIO_METADATA = {
  contentType: 'audio/mp4',
  customMetadata: {
    schoolId: 'school_1',
    logId: 'log_1',
    ownerUid: 'parent_1',
    studentId: 'student_1',
  },
};
const COVER_PATH = 'community_books/covers/9780141036144.jpg';
const COVER_METADATA = {
  contentType: 'image/jpeg',
  customMetadata: {
    schoolId: 'school_1',
    uploaderUid: 'teacher_1',
  },
};

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

async function seedAudioLog(uploaded = false, authorised = true) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const school = context.firestore().collection('schools').doc('school_1');
    await school.set({
      settings: {
        comprehensionRecording: authorised ? {
          enabled: true,
          authorityVersion: 'school-audio-v1-2026-07-17',
          authorityConfirmedAt: new Date(),
          retentionDays: 30,
        } : {enabled: true},
      },
    });
    await school.collection('readingLogs').doc('log_1').set({
        schoolId: 'school_1',
        classId: 'class_1',
        studentId: 'student_1',
        parentId: 'parent_1',
        loggedByRole: 'parent',
        comprehensionAudioUploaded: uploaded,
      });
  });
}

async function seedTeacher() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore()
      .collection('schools').doc('school_1')
      .collection('users').doc('teacher_1').set({
        schoolId: 'school_1',
        role: 'teacher',
      });
  });
}

async function seedUnrelatedParent() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const school = context.firestore().collection('schools').doc('school_1');
    await school.collection('parents').doc('parent_2').set({
      schoolId: 'school_1', role: 'parent', linkedChildren: ['student_2'],
    });
    await school.collection('students').doc('student_2').set({
      schoolId: 'school_1', classId: 'class_1', parentIds: ['parent_2'],
    });
  });
}

function audioRef(uid) {
  return ref(testEnv.authenticatedContext(uid).storage(), AUDIO_PATH);
}

test('comprehension audio: missing kill-switch doc fails closed', async () => {
  await seedAudioLog();
  await assertFails(uploadBytes(audioRef('parent_1'), AUDIO_BYTES, AUDIO_METADATA));
});

test('comprehension audio: owning parent can upload canonical object when enabled', async () => {
  await seedAudioLog();
  await seedFlag(true);
  await assertSucceeds(uploadBytes(audioRef('parent_1'), AUDIO_BYTES, AUDIO_METADATA));
});

test('comprehension audio: shared demo account cannot create unconfirmed uploads', async () => {
  await seedAudioLog();
  await seedFlag(true);
  const demoRef = ref(
    testEnv.authenticatedContext('parent_1', {
      demoAccount: true,
      demoSchoolId: 'school_1',
    }).storage(),
    AUDIO_PATH,
  );
  await assertFails(uploadBytes(demoRef, AUDIO_BYTES, AUDIO_METADATA));
});

test('comprehension audio: disabled kill switch denies upload', async () => {
  await seedAudioLog();
  await seedFlag(false);
  await assertFails(uploadBytes(audioRef('parent_1'), AUDIO_BYTES, AUDIO_METADATA));
});

test('comprehension audio: school authority and retention evidence fail closed', async () => {
  await seedAudioLog(false, false);
  await seedFlag(true);
  await assertFails(uploadBytes(audioRef('parent_1'), AUDIO_BYTES, AUDIO_METADATA));
});

test('comprehension audio: unauthenticated upload denied regardless of flag', async () => {
  await seedAudioLog();
  await seedFlag(true);
  const anonRef = ref(testEnv.unauthenticatedContext().storage(), AUDIO_PATH);
  await assertFails(uploadBytes(anonRef, AUDIO_BYTES, AUDIO_METADATA));
});

test('comprehension audio: non-audio content type denied even when enabled', async () => {
  await seedAudioLog();
  await seedFlag(true);
  await assertFails(
    uploadBytes(audioRef('parent_1'), AUDIO_BYTES, {
      ...AUDIO_METADATA,
      contentType: 'image/jpeg',
    }),
  );
});

test('comprehension audio: unrelated valid parent cannot upload another family\'s object', async () => {
  await seedAudioLog();
  await seedUnrelatedParent();
  await seedFlag(true);
  await assertFails(uploadBytes(audioRef('parent_2'), AUDIO_BYTES, {
    ...AUDIO_METADATA,
    customMetadata: {
      ...AUDIO_METADATA.customMetadata,
      ownerUid: 'parent_2',
    },
  }));
});

test('comprehension audio: metadata cannot redirect upload to another log or school', async () => {
  await seedAudioLog();
  await seedFlag(true);
  await assertFails(uploadBytes(audioRef('parent_1'), AUDIO_BYTES, {
    ...AUDIO_METADATA,
    customMetadata: {
      ...AUDIO_METADATA.customMetadata,
      logId: 'log_other',
    },
  }));
  const otherSchoolRef = ref(
    testEnv.authenticatedContext('parent_1').storage(),
    'comprehension_audio_uploads/school_2/log_1.m4a',
  );
  await assertFails(uploadBytes(otherSchoolRef, AUDIO_BYTES, AUDIO_METADATA));
});

test('comprehension audio: owner may retry but outsider cannot overwrite', async () => {
  await seedAudioLog();
  await seedFlag(true);
  await assertSucceeds(uploadBytes(audioRef('parent_1'), AUDIO_BYTES, AUDIO_METADATA));
  await assertSucceeds(uploadBytes(audioRef('parent_1'), AUDIO_BYTES, AUDIO_METADATA));
  await assertFails(uploadBytes(audioRef('parent_outsider'), AUDIO_BYTES, {
    ...AUDIO_METADATA,
    customMetadata: {
      ...AUDIO_METADATA.customMetadata,
      ownerUid: 'parent_outsider',
    },
  }));
});

test('comprehension audio: pending upload closes after server receipt', async () => {
  await seedAudioLog(true);
  await seedFlag(true);
  await assertFails(uploadBytes(audioRef('parent_1'), AUDIO_BYTES, AUDIO_METADATA));
});

test('comprehension audio: direct authenticated read is denied (signed-URL only)', async () => {
  // The object is seeded with rules disabled, then a normal authed client tries
  // to read it directly — denied (2.2). Playback must go through the
  // getComprehensionAudioUrl callable's signed URL, which bypasses these rules.
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await uploadBytes(
      ref(context.storage(), CANONICAL_AUDIO_PATH),
      AUDIO_BYTES,
      AUDIO_METADATA,
    );
  });
  await assertFails(getBytes(ref(
    testEnv.authenticatedContext('teacher_1').storage(),
    CANONICAL_AUDIO_PATH,
  )));
});

test('comprehension audio: clients cannot write the canonical playback object', async () => {
  await seedAudioLog();
  await seedFlag(true);
  const canonical = ref(
    testEnv.authenticatedContext('parent_1').storage(),
    CANONICAL_AUDIO_PATH,
  );
  await assertFails(uploadBytes(canonical, AUDIO_BYTES, AUDIO_METADATA));
});

test('community cover: verified teacher can create but cannot overwrite', async () => {
  await seedTeacher();
  const cover = ref(testEnv.authenticatedContext('teacher_1').storage(), COVER_PATH);
  await assertSucceeds(uploadBytes(cover, AUDIO_BYTES, COVER_METADATA));
  await assertFails(uploadBytes(cover, AUDIO_BYTES, COVER_METADATA));
});

test('community cover: shared demo accounts cannot mutate the global catalogue', async () => {
  await seedTeacher();
  const cover = ref(
    testEnv.authenticatedContext('teacher_1', {
      demoAccount: true,
      demoSchoolId: 'school_1',
    }).storage(),
    COVER_PATH,
  );
  await assertFails(uploadBytes(cover, AUDIO_BYTES, COVER_METADATA));
});

test('community cover: parent and unverified account cannot upload', async () => {
  await seedTeacher();
  const parentCover = ref(testEnv.authenticatedContext('parent_1').storage(), COVER_PATH);
  await assertFails(uploadBytes(parentCover, AUDIO_BYTES, {
    ...COVER_METADATA,
    customMetadata: {
      schoolId: 'school_1',
      uploaderUid: 'parent_1',
    },
  }));
  const forgedTeacherCover = ref(
    testEnv.authenticatedContext('outsider').storage(),
    COVER_PATH,
  );
  await assertFails(uploadBytes(forgedTeacherCover, AUDIO_BYTES, {
    ...COVER_METADATA,
    customMetadata: {
      schoolId: 'school_1',
      uploaderUid: 'outsider',
    },
  }));
});
