#!/usr/bin/env node
/**
 * Seed a self-contained demo school for Apple App Review.
 *
 * App Review testers cannot receive SMS, and Lumi's normal sign-in can involve
 * a phone one-time code (parents) or multi-factor SMS (teachers who enrolled
 * it). This script creates Firebase Auth users with **email + password and NO
 * enrolled second factor**, so the reviewer logs in with email/password and is
 * never challenged for an SMS code. It also writes the Firestore docs the app
 * needs after login (school, class, student, teacher, parent, the email→school
 * lookup index, and a couple of sample reading logs).
 *
 * What it creates:
 *   - a demo school, class, and one student (with a live `access` entitlement)
 *   - a TEACHER login  → demonstrates the class roster + logging reading on a
 *     student's behalf (the teacher-proxy flow)
 *   - a PARENT login    → demonstrates the family-side reading log
 *
 * The reviewer credentials are printed at the end and should be copied into
 * docs/app-store/app-review-notes.md / App Store Connect "App Review
 * Information".
 *
 * Idempotent: fixed document IDs + getUserByEmail-or-create, so re-running
 * refreshes the data without creating duplicates.
 *
 * Usage (writes to PRODUCTION lumi-ninc-au — run deliberately):
 *   FIREBASE_ADMIN_SERVICE_ACCOUNT_PATH=/abs/path/to/service-account.json \
 *     node scripts/seed_demo_review_account.js
 *
 *   OR with Application Default Credentials:
 *     gcloud auth application-default login
 *     GOOGLE_CLOUD_PROJECT=lumi-ninc-au node scripts/seed_demo_review_account.js
 *
 * DEMO_PASSWORD is required and must be supplied from a password manager.
 */

const path = require('path');
const fs = require('fs');

// firebase-admin lives in functions/node_modules in this repo; resolve it from
// there so the script runs regardless of the current working directory.
function loadAdmin() {
  try {
    return require('firebase-admin');
  } catch (_) {
    const fromFunctions = require.resolve('firebase-admin', {
      paths: [path.join(__dirname, '..', 'functions', 'node_modules')],
    });
    return require(fromFunctions);
  }
}
const admin = loadAdmin();
const crypto = require('crypto');

// ── Config ────────────────────────────────────────────────────────────────
const PROJECT_ID = process.env.GOOGLE_CLOUD_PROJECT || 'lumi-ninc-au';
const PASSWORD = process.env.DEMO_PASSWORD;
if (!PASSWORD || PASSWORD.length < 16) {
  die(
    'DEMO_PASSWORD is required and must be at least 16 characters. ' +
      'No App Review password is stored in Git.',
  );
}
const ACADEMIC_YEAR = 2026;

const SCHOOL_ID = 'demo-review-school';
const SCHOOL_NAME = 'Lumi Demo School';
const CLASS_ID = 'demo-review-class';
const CLASS_NAME = 'Demo Class';
const STUDENT_ID = 'demo-review-student';

const TEACHER = {
  email: 'review.teacher@lumi-reading.com',
  fullName: 'Demo Teacher',
  // Australian reserved example-number range (0491 570 xxx); never delivers SMS.
  phone: '+61491570156',
};
const PARENT = {
  email: 'review.parent@lumi-reading.com',
  fullName: 'Demo Parent',
  phone: '+61491570157',
};

function die(msg, code = 1) {
  process.stderr.write(`${msg}\n`);
  process.exit(code);
}

// Mirrors UserSchoolIndexService._hashEmail (lowercase + trim, SHA-256 hex).
function hashEmail(email) {
  return crypto.createHash('sha256').update(email.toLowerCase().trim()).digest('hex');
}

function initApp() {
  const saPath = process.env.FIREBASE_ADMIN_SERVICE_ACCOUNT_PATH;
  if (saPath) {
    if (!fs.existsSync(saPath)) die(`Service account file not found at ${saPath}`);
    admin.initializeApp({
      credential: admin.credential.cert(JSON.parse(fs.readFileSync(saPath, 'utf-8'))),
      projectId: PROJECT_ID,
    });
  } else {
    admin.initializeApp({ projectId: PROJECT_ID });
  }
}

// Create the Auth user (email + password, no MFA) or reuse + reset password.
async function ensureAuthUser({ email, fullName }) {
  const auth = admin.auth();
  try {
    const existing = await auth.getUserByEmail(email);
    await auth.updateUser(existing.uid, {
      password: PASSWORD,
      displayName: fullName,
      emailVerified: true,
    });
    return existing.uid;
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    const created = await auth.createUser({
      email,
      password: PASSWORD,
      displayName: fullName,
      emailVerified: true,
    });
    return created.uid;
  }
}

async function main() {
  initApp();
  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const expiresAt = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + 365 * 24 * 60 * 60 * 1000),
  );

  const teacherUid = await ensureAuthUser(TEACHER);
  const parentUid = await ensureAuthUser(PARENT);

  const school = db.collection('schools').doc(SCHOOL_ID);

  await school.set(
    { name: SCHOOL_NAME, createdBy: teacherUid, isDemo: true, createdAt: now },
    { merge: true },
  );

  // Teacher user doc — class membership is via the class doc's teacherIds
  // (the source of truth the reading-log rules check).
  await school.collection('users').doc(teacherUid).set(
    {
      role: 'teacher',
      schoolId: SCHOOL_ID,
      email: TEACHER.email,
      fullName: TEACHER.fullName,
      phoneNumber: TEACHER.phone,
      phoneVerified: true, // cosmetic; no real Firebase MFA factor is enrolled
      classIds: [CLASS_ID],
      isActive: true,
      createdAt: now,
    },
    { merge: true },
  );

  // Parent doc — phoneVerified:false so the app does not treat MFA as enrolled.
  await school.collection('parents').doc(parentUid).set(
    {
      role: 'parent',
      schoolId: SCHOOL_ID,
      email: PARENT.email,
      fullName: PARENT.fullName,
      phoneNumber: PARENT.phone,
      phoneVerified: false,
      linkedChildren: [STUDENT_ID],
      relationshipLabel: 'Parent',
      isActive: true,
      createdAt: now,
    },
    { merge: true },
  );

  await school.collection('classes').doc(CLASS_ID).set(
    {
      schoolId: SCHOOL_ID,
      name: CLASS_NAME,
      teacherId: teacherUid,
      teacherIds: [teacherUid],
      studentIds: [STUDENT_ID],
      defaultMinutesTarget: 15,
      isActive: true,
      createdBy: teacherUid,
      createdAt: now,
    },
    { merge: true },
  );

  // Student — `access` must be live (active + future expiry) for parent logging.
  // merge:true preserves stats recomputed by the aggregateStudentStats function.
  await school.collection('students').doc(STUDENT_ID).set(
    {
      firstName: 'Riley',
      lastName: 'Reader',
      schoolId: SCHOOL_ID,
      classId: CLASS_ID,
      parentIds: [parentUid],
      currentReadingLevel: 'Level 10',
      isActive: true,
      createdAt: now,
      access: {
        status: 'active',
        academicYear: ACADEMIC_YEAR,
        expiresAt,
        source: 'demo',
        grantedBy: teacherUid,
        grantedAt: now,
      },
      guardianProfiles: {
        [parentUid]: { name: PARENT.fullName, relationshipLabel: 'Parent' },
      },
    },
    { merge: true },
  );

  // Email → school lookup index (what sign-in reads to resolve the account).
  const indexCol = db.collection('userSchoolIndex');
  await indexCol.doc(hashEmail(TEACHER.email)).set(
    { email: TEACHER.email, schoolId: SCHOOL_ID, userType: 'user', userId: teacherUid, updatedAt: now },
    { merge: true },
  );
  await indexCol.doc(hashEmail(PARENT.email)).set(
    { email: PARENT.email, schoolId: SCHOOL_ID, userType: 'parent', userId: parentUid, updatedAt: now },
    { merge: true },
  );

  // A couple of sample reading logs so the demo isn't empty. Fixed IDs keep it
  // idempotent; the stats function recomputes the student's totals on write.
  const logs = school.collection('readingLogs');
  const dayMs = 24 * 60 * 60 * 1000;
  await logs.doc('demo-log-parent').set(
    {
      studentId: STUDENT_ID,
      parentId: parentUid,
      schoolId: SCHOOL_ID,
      classId: CLASS_ID,
      date: admin.firestore.Timestamp.fromDate(new Date(Date.now() - 1 * dayMs)),
      minutesRead: 20,
      targetMinutes: 15,
      status: 'completed',
      bookTitles: ['The Very Hungry Caterpillar'],
      loggedByName: PARENT.fullName,
      loggedByLabel: 'Logged by Demo Parent',
      loggedByRole: 'parent',
      createdAt: now,
    },
    { merge: true },
  );
  await logs.doc('demo-log-teacher').set(
    {
      studentId: STUDENT_ID,
      parentId: teacherUid, // teacher-proxy logs carry the teacher's uid here
      schoolId: SCHOOL_ID,
      classId: CLASS_ID,
      date: admin.firestore.Timestamp.fromDate(new Date(Date.now() - 3 * dayMs)),
      minutesRead: 15,
      targetMinutes: 15,
      status: 'completed',
      bookTitles: ['Where the Wild Things Are'],
      loggedByName: TEACHER.fullName,
      loggedByLabel: 'Logged by Demo Teacher',
      loggedByRole: 'teacher',
      createdAt: now,
    },
    { merge: true },
  );

  process.stdout.write(
    [
      '',
      '✓ Demo review data seeded into project ' + PROJECT_ID + '.',
      '',
      '  Reviewer credentials (paste into App Store Connect → App Review Information):',
      '    Teacher login  email: ' + TEACHER.email,
      '                password: <the DEMO_PASSWORD secret supplied to this run>',
      '    Parent login   email: ' + PARENT.email,
      '                password: <the DEMO_PASSWORD secret supplied to this run>',
      '',
      '  Both sign in with email + password (no SMS code required).',
      '  School: ' + SCHOOL_NAME + ' · Class: ' + CLASS_NAME + ' · Student: Riley Reader',
      '',
    ].join('\n'),
  );
  process.exit(0);
}

main().catch((e) => die(`Seed failed: ${e.stack || e}`));
