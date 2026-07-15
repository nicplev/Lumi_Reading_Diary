#!/usr/bin/env node
/**
 * Restore sign-in for a parent whose Firebase Auth user was deleted out-of-band
 * while their Firestore data was left behind (the "ghost parent" case the
 * school portal's Parent Connections tab surfaces as "Removed").
 *
 * It recreates the Auth user **with the same UID as the existing parent doc**,
 * so every existing linkage stays intact:
 *   - schools/{schoolId}/parents/{uid}          (the parent record)
 *   - students[].parentIds / parent.linkedChildren (bidirectional links)
 *   - userSchoolIndex/{sha256(email)}            (the sign-in lookup)
 *
 * The recreated user has **email + password and NO enrolled second factor**, and
 * the parent doc's phoneVerified is forced false, so sign-in is a plain
 * email/password with no SMS/MFA challenge — ideal for testing.
 *
 * Idempotent: if the Auth user already exists, its password is just reset.
 *
 * Usage (writes to PRODUCTION lumi-ninc-au — run deliberately):
 *   # Application Default Credentials:
 *   gcloud auth application-default login
 *   GOOGLE_CLOUD_PROJECT=lumi-ninc-au \
 *     node scripts/restore_parent_login.js support+student00@lumi-reading.com
 *
 *   # …or a service account:
 *   FIREBASE_ADMIN_SERVICE_ACCOUNT_PATH=/abs/path/sa.json \
 *     node scripts/restore_parent_login.js support+student00@lumi-reading.com
 *
 * Multiple emails may be passed. Override the password with RESTORE_PASSWORD=...
 */

const path = require('path');
const fs = require('fs');
const crypto = require('crypto');

// firebase-admin lives in functions/node_modules in this repo; resolve from
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

const PROJECT_ID = process.env.GOOGLE_CLOUD_PROJECT || 'lumi-ninc-au';
const PASSWORD = process.env.RESTORE_PASSWORD;

function die(msg, code = 1) {
  process.stderr.write(`${msg}\n`);
  process.exit(code);
}

if (!PASSWORD || PASSWORD.length < 16) {
  die('RESTORE_PASSWORD is required and must be at least 16 characters.');
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

/**
 * Resolve a parent's uid + schoolId from their email. Prefers the
 * userSchoolIndex lookup (no composite index needed); falls back to a
 * collectionGroup scan if the index entry is gone too.
 */
async function resolveParent(db, email) {
  const idxSnap = await db.collection('userSchoolIndex').doc(hashEmail(email)).get();
  if (idxSnap.exists) {
    const d = idxSnap.data() || {};
    if (d.userId && d.schoolId) {
      return { uid: d.userId, schoolId: d.schoolId, fromIndex: true };
    }
  }
  // Fallback: scan parent docs across schools by email.
  try {
    const cg = await db.collectionGroup('parents').where('email', '==', email).limit(1).get();
    if (!cg.empty) {
      const doc = cg.docs[0];
      return { uid: doc.id, schoolId: doc.data().schoolId, fromIndex: false };
    }
  } catch (e) {
    die(
      `Could not look up "${email}". The userSchoolIndex entry is missing and the ` +
        `collectionGroup('parents') fallback failed (likely a missing index):\n  ${e.message}`
    );
  }
  return null;
}

async function restoreOne(db, auth, email) {
  const resolved = await resolveParent(db, email);
  if (!resolved) {
    process.stdout.write(`  ✗ ${email}: no parent record found (skipped)\n`);
    return false;
  }
  const { uid, schoolId } = resolved;

  const parentRef = db.collection('schools').doc(schoolId).collection('parents').doc(uid);
  const parentSnap = await parentRef.get();
  if (!parentSnap.exists) {
    process.stdout.write(
      `  ✗ ${email}: index points at ${schoolId}/${uid} but that parent doc is gone (skipped)\n`
    );
    return false;
  }
  const parent = parentSnap.data() || {};
  const fullName = parent.fullName || 'Parent';

  // Recreate (or refresh) the Auth user with the existing uid, no second factor.
  let action;
  try {
    await auth.getUser(uid);
    await auth.updateUser(uid, { password: PASSWORD, emailVerified: true, displayName: fullName });
    action = 'reset existing Auth user';
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    try {
      await auth.createUser({ uid, email, password: PASSWORD, emailVerified: true, displayName: fullName });
      action = 'recreated Auth user';
    } catch (e2) {
      if (e2.code === 'auth/email-already-exists') {
        const other = await auth.getUserByEmail(email);
        process.stdout.write(
          `  ✗ ${email}: another Auth user (uid ${other.uid}) already owns this email; ` +
            `not touching it to avoid breaking Firestore links (skipped)\n`
        );
        return false;
      }
      throw e2;
    }
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  // phoneVerified:false → app treats MFA as not enrolled, so it's a plain
  // email/password sign-in (the recreated Auth user has no second factor).
  await parentRef.set({ phoneVerified: false, isActive: true }, { merge: true });
  await db.collection('userSchoolIndex').doc(hashEmail(email)).set(
    { email, schoolId, userType: 'parent', userId: uid, updatedAt: now },
    { merge: true }
  );

  process.stdout.write(`  ✓ ${email}: ${action} · school ${schoolId} · uid ${uid}\n`);
  return true;
}

async function main() {
  const emails = process.argv.slice(2).filter((a) => a.includes('@'));
  if (emails.length === 0) {
    die('Usage: node scripts/restore_parent_login.js <email> [<email> ...]');
  }

  initApp();
  const db = admin.firestore();
  const auth = admin.auth();

  process.stdout.write(`Restoring parent login(s) in project ${PROJECT_ID}:\n`);
  let restored = 0;
  for (const email of emails) {
    if (await restoreOne(db, auth, email)) restored++;
  }

  process.stdout.write(
    [
      '',
      `✓ ${restored}/${emails.length} parent login(s) restored.`,
      '',
      '  Sign in with email + password (no SMS/MFA challenge):',
      ...emails.map((e) => `    ${e}  /  ${PASSWORD}`),
      '',
    ].join('\n')
  );
  process.exit(0);
}

main().catch((e) => die(`Restore failed: ${e.stack || e}`));
