#!/usr/bin/env node
/**
 * Delete "ghost" parent records — Firestore parent docs whose Firebase Auth
 * user no longer exists (the Auth account was deleted out-of-band, leaving the
 * doc, the userSchoolIndex entry, and the student links behind).
 *
 * SAFETY: a parent is only deleted when its Auth user is confirmed MISSING. Any
 * target that still has a live Auth user is skipped — so this can never remove a
 * real account, even if you point it at the wrong email/phone.
 *
 * Dry-run by default; pass --apply to actually delete. For each ghost it:
 *   - removes the uid from every linked student's `parentIds` and deletes the
 *     student's `guardianProfiles.<uid>` entry
 *   - deletes the userSchoolIndex lookup entries that point at the uid
 *   - deletes the parent doc
 *   - best-effort deletes the (already-missing) Auth user and decrements
 *     school.parentCount
 *
 * Usage (PRODUCTION lumi-ninc-au — run deliberately):
 *   GOOGLE_CLOUD_PROJECT=lumi-ninc-au node scripts/cleanup_ghost_parents.js \
 *     --school beaumaris_primary_school \
 *     --target support+student00@lumi-reading.com \
 *     --target +61400000000 --target +61421701249 \
 *     [--apply]
 */

const path = require('path');
const fs = require('fs');
const crypto = require('crypto');

function loadAdmin() {
  try {
    return require('firebase-admin');
  } catch (_) {
    return require(require.resolve('firebase-admin', {
      paths: [path.join(__dirname, '..', 'functions', 'node_modules')],
    }));
  }
}
const admin = loadAdmin();
const PROJECT_ID = process.env.GOOGLE_CLOUD_PROJECT || 'lumi-ninc-au';

function die(msg, code = 1) { process.stderr.write(`${msg}\n`); process.exit(code); }
function hashEmail(v) { return crypto.createHash('sha256').update(v.toLowerCase().trim()).digest('hex'); }

function parseArgs(argv) {
  const out = { targets: [], uids: [], apply: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--school') out.school = argv[++i];
    else if (a === '--target') out.targets.push(argv[++i]);
    else if (a === '--uid') out.uids.push(argv[++i]);
    else if (a === '--apply') out.apply = true;
    else die(`Unknown argument: ${a}`);
  }
  if (!out.school) die('Missing --school <schoolId>');
  if (out.targets.length === 0 && out.uids.length === 0) {
    die('Missing --uid <parentUid> or --target <email|phone> (either repeatable)');
  }
  return out;
}

function initApp() {
  const saPath = process.env.FIREBASE_ADMIN_SERVICE_ACCOUNT_PATH;
  if (saPath) {
    if (!fs.existsSync(saPath)) die(`Service account file not found at ${saPath}`);
    admin.initializeApp({ credential: admin.credential.cert(JSON.parse(fs.readFileSync(saPath, 'utf-8'))), projectId: PROJECT_ID });
  } else {
    admin.initializeApp({ projectId: PROJECT_ID });
  }
}

async function authMissing(auth, uid) {
  try { await auth.getUser(uid); return false; }
  catch (e) { if (e.code === 'auth/user-not-found') return true; throw e; }
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  initApp();
  const db = admin.firestore();
  const auth = admin.auth();

  process.stdout.write(
    `Cleanup ghost parents in ${opts.school} (${PROJECT_ID}) — ${opts.apply ? 'APPLY' : 'DRY-RUN'}\n` +
    `${opts.uids.length ? `UIDs: ${opts.uids.join(', ')}\n` : ''}` +
    `${opts.targets.length ? `Targets: ${opts.targets.join(', ')}\n` : ''}\n`
  );

  const parentsCol = db.collection('schools').doc(opts.school).collection('parents');
  const byId = new Map();

  // Explicit uids — one uid is exactly one parent record, no inference.
  for (const uid of opts.uids) {
    const snap = await parentsCol.doc(uid).get();
    if (!snap.exists) { process.stdout.write(`  (uid ${uid} not found — skipped)\n`); continue; }
    byId.set(snap.id, snap);
  }
  // Optional email/phone targets — matched against the school's parents.
  if (opts.targets.length) {
    const parentsSnap = await parentsCol.get();
    const targetSet = new Set(opts.targets.map((t) => t.trim()));
    for (const d of parentsSnap.docs) {
      const data = d.data();
      if (targetSet.has((data.email || '').trim()) || targetSet.has((data.phoneNumber || '').trim())) {
        byId.set(d.id, d);
      }
    }
  }
  const matched = [...byId.values()];

  if (matched.length === 0) die('No parent docs matched — nothing to do.');

  let deleted = 0;
  for (const doc of matched) {
    const data = doc.data();
    const uid = doc.id;
    const label = `${data.fullName || '(no name)'} <${data.email || data.phoneNumber || '?'}> uid=${uid}`;

    // SAFETY GATE: never delete a parent whose Auth user still exists.
    if (!(await authMissing(auth, uid))) {
      process.stdout.write(`  SKIP (Auth EXISTS — real account): ${label}\n`);
      continue;
    }

    const linkedChildren = Array.isArray(data.linkedChildren) ? data.linkedChildren : [];

    // Index entries pointing at this uid (hash-derived + any others by query).
    const indexIds = new Set();
    if (data.email) indexIds.add(hashEmail(data.email));
    if (data.phoneNumber) indexIds.add(hashEmail(data.phoneNumber));
    try {
      const idxSnap = await db.collection('userSchoolIndex').where('userId', '==', uid).get();
      idxSnap.docs.forEach((d) => indexIds.add(d.id));
    } catch (e) {
      process.stdout.write(`    (userSchoolIndex query failed, using hash ids only: ${e.message})\n`);
    }

    process.stdout.write(
      `  GHOST: ${label}\n` +
      `    - unlink from ${linkedChildren.length} student(s): ${linkedChildren.join(', ') || '(none)'}\n` +
      `    - delete ${indexIds.size} index entr(ies)\n` +
      `    - delete parent doc\n`
    );

    if (!opts.apply) continue;

    const batch = db.batch();
    for (const sid of linkedChildren) {
      const sref = db.collection('schools').doc(opts.school).collection('students').doc(sid);
      batch.update(sref, {
        parentIds: admin.firestore.FieldValue.arrayRemove(uid),
        [`guardianProfiles.${uid}`]: admin.firestore.FieldValue.delete(),
      });
    }
    for (const id of indexIds) batch.delete(db.collection('userSchoolIndex').doc(id));
    batch.delete(doc.ref);
    await batch.commit();

    try { await auth.deleteUser(uid); } catch (e) { /* already gone */ }
    try {
      await db.collection('schools').doc(opts.school).update({
        parentCount: admin.firestore.FieldValue.increment(-1),
      });
    } catch (e) { /* non-critical */ }

    deleted++;
    process.stdout.write('    ✓ deleted\n');
  }

  process.stdout.write(
    `\n${opts.apply ? `✓ Deleted ${deleted} ghost parent(s).` : 'Dry-run only — re-run with --apply to delete.'}\n`
  );
  process.exit(0);
}

main().catch((e) => die(`Cleanup failed: ${e.stack || e}`));
