// Verifies what storage.rules can actually enforce: authentication, the
// claimed-owner metadata contract, path/filename binding, size and content
// type — plus who may overwrite an object that already exists.
//
// It does NOT verify the kill switch, per-school audio authority, retention
// evidence, or whether a logId really belongs to the uploading parent. Those
// need Firestore reads, and Storage rules cannot read Firestore in this
// project (see the NOTE block in storage.rules). Until 2026-07-20 this file
// asserted them anyway; those tests passed only because the broken
// firestore.get() denied every write, so "denied" was indistinguishable from
// "correctly gated" — a green suite over rules that blocked all uploads for
// five days. The gates live server-side in confirmComprehensionAudioUpload
// and are covered where they are real:
//   comprehension_audio.integration.test.js:204  disabled flag + non-owner
//   comprehension_audio.integration.test.js:225  school authority evidence
//   comprehension_audio.integration.test.js:271  playback kill switch
//   comprehension_retention.test.js:136          authority version/retention
//
// Requires BOTH emulators (Firestore is still seeded for firestore.rules
// coverage in the same harness):
//   npm run test:rules:storage
const path = require('path');
const fs = require('fs');
const { test, before, after, beforeEach } = require('node:test');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {
  ref, uploadBytes, getBytes, deleteObject,
} = require('firebase/storage');

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

async function seedAudioLog(
  uploaded = false,
  authorised = true,
  retentionDays = 30,
) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const school = context.firestore().collection('schools').doc('school_1');
    await school.set({
      settings: {
        comprehensionRecording: authorised ? {
          enabled: true,
          authorityVersion: 'school-audio-v1-2026-07-17',
          authorityConfirmedAt: new Date(),
          retentionDays,
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

// The storage layer intentionally does not consult the kill switch, the
// per-school authority evidence, or the reading log. A staged upload is
// inert: reads are denied, and confirmComprehensionAudioUpload re-validates
// everything with Admin credentials before promoting anything. These two
// tests pin that intent so a future reader does not "restore" a Firestore
// lookup here and break every upload for the third time.
test('comprehension audio: staging does not depend on the kill-switch doc',
  async () => {
    await seedAudioLog();
    // No seedFlag() at all — the flag doc does not exist.
    await assertSucceeds(
      uploadBytes(audioRef('parent_1'), AUDIO_BYTES, AUDIO_METADATA));
  });

test('comprehension audio: staging does not depend on school authority',
  async () => {
    await seedAudioLog(false, false);
    await seedFlag(false);
    await assertSucceeds(
      uploadBytes(audioRef('parent_1'), AUDIO_BYTES, AUDIO_METADATA));
  });

test('comprehension audio: owning parent can stage their own pending object', async () => {
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

test('comprehension audio: oversize payload denied', async () => {
  await seedAudioLog();
  await seedFlag(true);
  await assertFails(uploadBytes(
    audioRef('parent_1'), new Uint8Array(2 * 1024 * 1024 + 1), AUDIO_METADATA));
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

// Rules cannot tell whose reading log a logId belongs to, so a first write
// to an unused logId is not attributable at this layer — it is staged and
// then rejected by the confirm callable, which checks the log's parentId
// (comprehension_audio.integration.test.js:204, "non-owner"). What rules DO
// prevent is the damaging half: taking over an object its owner has already
// staged. Asserting the honest boundary rather than a denial we cannot make.
test('comprehension audio: outsider cannot take over an already-staged object',
  async () => {
    await seedAudioLog();
    await seedUnrelatedParent();
    await seedFlag(true);
    // Distinct paths: clearStorage() mid-test does not take effect, which
    // would turn the second create into an overwrite and mask the result.
    const unclaimed = ref(
      testEnv.authenticatedContext('parent_2').storage(),
      'comprehension_audio_uploads/school_1/log_unclaimed.m4a',
    );
    // Unattributable first write: allowed here, refused server-side.
    await assertSucceeds(uploadBytes(unclaimed, AUDIO_BYTES, {
      ...AUDIO_METADATA,
      customMetadata: {
        ...AUDIO_METADATA.customMetadata,
        logId: 'log_unclaimed',
        ownerUid: 'parent_2',
      },
    }));

    // Once the rightful owner has staged, parent_2 cannot overwrite it.
    await assertSucceeds(
      uploadBytes(audioRef('parent_1'), AUDIO_BYTES, AUDIO_METADATA));
    await assertFails(uploadBytes(audioRef('parent_2'), AUDIO_BYTES, {
      ...AUDIO_METADATA,
      customMetadata: {...AUDIO_METADATA.customMetadata, ownerUid: 'parent_2'},
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

test('comprehension audio: pending objects cannot be deleted from a client',
  async () => {
    await seedAudioLog();
    await seedFlag(true);
    await assertSucceeds(
      uploadBytes(audioRef('parent_1'), AUDIO_BYTES, AUDIO_METADATA));
    // The server removes collected pending objects with Admin credentials;
    // a client deleting them would strand the confirm callable.
    await assertFails(deleteObject(audioRef('parent_1')));
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

// PR #481 deliberately relaxed this: the original contributor may replace
// their own cover (fixing a blurry photo), but nobody else may.
test('community cover: uploader may replace their own cover, others may not',
  async () => {
    await seedTeacher();
    const cover = ref(
      testEnv.authenticatedContext('teacher_1').storage(), COVER_PATH);
    await assertSucceeds(uploadBytes(cover, AUDIO_BYTES, COVER_METADATA));
    await assertSucceeds(uploadBytes(cover, AUDIO_BYTES, COVER_METADATA));

    const otherCover = ref(
      testEnv.authenticatedContext('teacher_2').storage(), COVER_PATH);
    await assertFails(uploadBytes(otherCover, AUDIO_BYTES, {
      ...COVER_METADATA,
      customMetadata: {schoolId: 'school_1', uploaderUid: 'teacher_2'},
    }));
  });

// Legacy covers predate custom metadata, so they carry no uploaderUid, match
// nobody, and are immutable from any client. Replacing one needs a backend
// path with Admin credentials — the intended fail-closed outcome.
test('community cover: legacy cover without uploaderUid is immutable',
  async () => {
    await seedTeacher();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await uploadBytes(ref(context.storage(), COVER_PATH), AUDIO_BYTES, {
        contentType: 'image/jpeg',
      });
    });
    const cover = ref(
      testEnv.authenticatedContext('teacher_1').storage(), COVER_PATH);
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

// Staff-only creation was enforced via a Firestore lookup that never worked
// and blocked ALL cover uploads from 2026-07-15. Accounts are invite-only, so
// any authenticated non-demo user may now create a cover; what is still
// enforced is that the claimed uploaderUid must be the caller's own, which is
// what makes the overwrite rule above meaningful.
test('community cover: uploaderUid must be the caller, not a claimed identity',
  async () => {
    await seedTeacher();
    const forged = ref(
      testEnv.authenticatedContext('outsider').storage(), COVER_PATH);
    await assertFails(uploadBytes(forged, AUDIO_BYTES, {
      ...COVER_METADATA,
      customMetadata: {schoolId: 'school_1', uploaderUid: 'teacher_1'},
    }));

    const missingUploader = ref(
      testEnv.authenticatedContext('teacher_1').storage(), COVER_PATH);
    await assertFails(uploadBytes(missingUploader, AUDIO_BYTES, {
      ...COVER_METADATA,
      customMetadata: {schoolId: 'school_1'},
    }));
  });

test('community cover: non-jpeg and oversize uploads denied', async () => {
  await seedTeacher();
  const cover = ref(
    testEnv.authenticatedContext('teacher_1').storage(), COVER_PATH);
  await assertFails(uploadBytes(cover, AUDIO_BYTES, {
    ...COVER_METADATA,
    contentType: 'image/png',
  }));
  await assertFails(uploadBytes(
    cover, new Uint8Array(2 * 1024 * 1024 + 1), COVER_METADATA));
});
