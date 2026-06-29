#!/usr/bin/env node
/**
 * Set up a parent account end-to-end: ensure a working email/password sign-in
 * (no MFA), then redeem one or more student link codes to connect the parent to
 * students — exactly as the app's `linkParentToStudent` Cloud Function would.
 *
 * Use this to restore a "ghost" parent (Auth user deleted, Firestore doc left
 * behind) or to wire up a test parent from scratch, and link them to students
 * via link codes generated in the portal's Link Codes tab.
 *
 * What it does:
 *   1. Resolves the parent's uid + schoolId (userSchoolIndex → collectionGroup
 *      'parents' by email → falls back to the first link code's schoolId).
 *   2. Recreates/refreshes the Firebase Auth user (email + password, NO second
 *      factor) keeping the existing uid so all links + index stay intact.
 *   3. Ensures a parent doc exists (creates a minimal one only if none found),
 *      forces phoneVerified:false so sign-in is a plain email/password.
 *   4. Writes the userSchoolIndex email lookup.
 *   5. Redeems each link code in an atomic transaction — a faithful port of
 *      functions/src/parent_linking.ts linkParentToStudentCore, including the
 *      first-link book-pack `access` grant (functions/src/access.ts). The
 *      deployed refreshGuardianProfilesOnLink trigger fills guardianProfiles.
 *
 * Idempotent: re-running resets the password and skips already-linked students.
 *
 * Usage (writes to PRODUCTION lumi-ninc-au — run deliberately):
 *   gcloud auth application-default login
 *   GOOGLE_CLOUD_PROJECT=lumi-ninc-au node scripts/setup_parent_account.js \
 *     --email support+student0@lumi-reading.com \
 *     --code ARY6T5RD --code H522WZDQ
 *
 *   # …or with a service account:
 *   FIREBASE_ADMIN_SERVICE_ACCOUNT_PATH=/abs/sa.json node scripts/setup_parent_account.js ...
 *
 * Flags:
 *   --email <addr>          (required) parent email
 *   --code <CODE>           (repeatable) link code to redeem
 *   --password <pw>         sign-in password (default LumiReview2026! or $RESTORE_PASSWORD)
 *   --name "<Full Name>"    fullName used only when CREATING a new parent doc
 *   --relationship <label>  relationship label for a new parent doc (default Parent)
 *   --phone <+E164>         phoneNumber for a new parent doc (optional)
 */

const path = require('path');
const fs = require('fs');
const crypto = require('crypto');

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
const DEFAULT_TIMEZONE = 'Australia/Sydney';
const COLL_LINK_CODES = 'studentLinkCodes';
const ACTIVE_SUBSCRIPTION_STATUSES = ['paid', 'comp', 'trial', 'grace'];

function die(msg, code = 1) {
  process.stderr.write(`${msg}\n`);
  process.exit(code);
}

// ── CLI parsing ─────────────────────────────────────────────────────────────
function parseArgs(argv) {
  const out = { codes: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = () => argv[++i];
    if (a === '--email') out.email = next();
    else if (a === '--code') out.codes.push(next());
    else if (a === '--password') out.password = next();
    else if (a === '--name') out.name = next();
    else if (a === '--relationship') out.relationship = next();
    else if (a === '--phone') out.phone = next();
    else die(`Unknown argument: ${a}`);
  }
  if (!out.email || !out.email.includes('@')) {
    die('Usage: node scripts/setup_parent_account.js --email <addr> [--code CODE ...]');
  }
  out.password = out.password || process.env.RESTORE_PASSWORD || 'LumiReview2026!';
  out.codes = out.codes.map((c) => c.trim().toUpperCase()).filter(Boolean);
  return out;
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

// ── Access helpers — faithful port of functions/src/access.ts ────────────────
function isActiveSubscriptionStatus(status) {
  return status != null && ACTIVE_SUBSCRIPTION_STATUSES.includes(status);
}

function timezoneOffsetMs(d, tz) {
  try {
    const dtf = new Intl.DateTimeFormat('en-US', {
      timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
    });
    const map = {};
    for (const p of dtf.formatToParts(d)) {
      if (p.type !== 'literal') map[p.type] = Number(p.value);
    }
    const asUtc = Date.UTC(
      map.year, map.month - 1, map.day,
      map.hour === 24 ? 0 : map.hour, map.minute, map.second
    );
    return asUtc - d.getTime();
  } catch {
    return 0;
  }
}

// End of January of the following calendar year, local time (AU/Sydney).
function hardExpiryFor(academicYear, tz = DEFAULT_TIMEZONE) {
  const naiveUtc = Date.UTC(academicYear + 1, 0, 31, 23, 59, 59);
  const offsetMs = timezoneOffsetMs(new Date(naiveUtc), tz);
  return new Date(naiveUtc - offsetMs);
}

function buildStudentAccess({ academicYear, source, grantedBy }) {
  return {
    status: 'active',
    academicYear,
    expiresAt: hardExpiryFor(academicYear),
    source,
    grantedAt: new Date(),
    grantedBy,
  };
}

function studentAccessAlreadyLive(studentData) {
  const access = studentData && studentData.access;
  if (!access || access.status !== 'active') return false;
  const exp = access.expiresAt;
  const expMs =
    exp instanceof admin.firestore.Timestamp ? exp.toMillis()
      : exp instanceof Date ? exp.getTime()
        : 0;
  return expMs > Date.now();
}

// ── Link-code parsing/selection — port of functions/src/parent_linking.ts ────
function parseExpiresAt(raw) {
  if (raw instanceof admin.firestore.Timestamp) return raw.toDate();
  if (raw instanceof Date) return raw;
  if (typeof raw === 'string') {
    const d = new Date(raw);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

function parseCodeDoc(snap) {
  const data = snap.data() || {};
  return {
    id: snap.id,
    code: String(data.code ?? '').toUpperCase(),
    status: data.status ?? '',
    studentId: String(data.studentId ?? ''),
    schoolId: String(data.schoolId ?? ''),
    expiresAt: parseExpiresAt(data.expiresAt ?? data.expiryDate),
  };
}

function codePriority(rec) {
  const now = new Date();
  const expired = rec.expiresAt !== null && rec.expiresAt < now;
  if (rec.status === 'active' && !expired) return 0;
  if (rec.status === 'used') return 1;
  if (rec.status === 'revoked') return 2;
  if (rec.status === 'expired' || expired) return 3;
  return 4;
}

async function findBestCodeForString(db, codeUpper) {
  const q = await db.collection(COLL_LINK_CODES).where('code', '==', codeUpper).limit(10).get();
  if (q.empty) return null;
  return q.docs.map(parseCodeDoc).sort((a, b) => codePriority(a) - codePriority(b))[0];
}

// ── Parent resolution + Auth restore ────────────────────────────────────────
async function resolveParent(db, email, codes) {
  const idxSnap = await db.collection('userSchoolIndex').doc(hashEmail(email)).get();
  if (idxSnap.exists) {
    const d = idxSnap.data() || {};
    if (d.userId && d.schoolId) return { uid: d.userId, schoolId: d.schoolId, exists: true };
  }
  try {
    const cg = await db.collectionGroup('parents').where('email', '==', email).limit(1).get();
    if (!cg.empty) {
      const doc = cg.docs[0];
      return { uid: doc.id, schoolId: doc.data().schoolId, exists: true };
    }
  } catch (e) {
    process.stderr.write(`  (collectionGroup parents lookup failed: ${e.message})\n`);
  }
  // No parent record — derive the school from a link code so we can create one.
  for (const code of codes) {
    const best = await findBestCodeForString(db, code);
    if (best && best.schoolId) return { uid: null, schoolId: best.schoolId, exists: false };
  }
  return null;
}

async function ensureAuthUser(auth, { uid, email, password, fullName }) {
  if (uid) {
    try {
      await auth.getUser(uid);
      await auth.updateUser(uid, { password, emailVerified: true, displayName: fullName });
      return { uid, action: 'reset existing Auth user' };
    } catch (e) {
      if (e.code !== 'auth/user-not-found') throw e;
      await auth.createUser({ uid, email, password, emailVerified: true, displayName: fullName });
      return { uid, action: 'recreated Auth user (existing uid)' };
    }
  }
  // No existing doc/uid — create a brand-new Auth user (letting Firebase assign).
  try {
    const created = await auth.createUser({ email, password, emailVerified: true, displayName: fullName });
    return { uid: created.uid, action: 'created new Auth user' };
  } catch (e) {
    if (e.code !== 'auth/email-already-exists') throw e;
    const existing = await auth.getUserByEmail(email);
    await auth.updateUser(existing.uid, { password, emailVerified: true, displayName: fullName });
    return { uid: existing.uid, action: 'reset existing Auth user (matched by email)' };
  }
}

// ── Redemption — faithful port of linkParentToStudentCore ────────────────────
async function redeemCode(db, uid, codeUpper) {
  const best = await findBestCodeForString(db, codeUpper);
  if (!best) return { ok: false, reason: 'invalid-code (not recognised)' };

  return db.runTransaction(async (tx) => {
    const codeRef = db.collection(COLL_LINK_CODES).doc(best.id);
    const codeSnap = await tx.get(codeRef);
    if (!codeSnap.exists) return { ok: false, reason: 'invalid-code' };
    const fresh = parseCodeDoc(codeSnap);
    if (fresh.code !== codeUpper) return { ok: false, reason: 'invalid-code' };
    if (fresh.status === 'used') {
      return { ok: false, reason: `already used (by ${codeSnap.data().usedBy || 'unknown'})` };
    }
    if (fresh.status === 'revoked') return { ok: false, reason: 'revoked' };
    if (!fresh.expiresAt) return { ok: false, reason: 'malformed (no expiry)' };
    if (fresh.status === 'expired' || fresh.expiresAt < new Date()) return { ok: false, reason: 'expired' };
    if (fresh.status !== 'active') return { ok: false, reason: `status ${fresh.status}` };
    if (!fresh.schoolId || !fresh.studentId) return { ok: false, reason: 'malformed' };

    const parentRef = db.collection('schools').doc(fresh.schoolId).collection('parents').doc(uid);
    const parentSnap = await tx.get(parentRef);
    if (!parentSnap.exists) return { ok: false, reason: 'parent-doc-missing' };

    const studentRef = db.collection('schools').doc(fresh.schoolId).collection('students').doc(fresh.studentId);
    const studentSnap = await tx.get(studentRef);
    if (!studentSnap.exists) return { ok: false, reason: 'student-missing' };

    // First-link book-pack access (only if no live access + school sub active).
    const cfgSnap = await tx.get(db.collection('config').doc('academicYear'));
    const currentYear = cfgSnap.data() && cfgSnap.data().currentAcademicYear;
    let subActive = false;
    if (typeof currentYear === 'number') {
      const subSnap = await tx.get(
        db.collection('schoolSubscriptions').doc(`${fresh.schoolId}_${currentYear}`)
      );
      subActive = subSnap.exists && isActiveSubscriptionStatus(subSnap.data() && subSnap.data().status);
    }
    const grantAccess =
      typeof currentYear === 'number' && subActive && !studentAccessAlreadyLive(studentSnap.data());

    const existingLinked = Array.isArray(parentSnap.data().linkedChildren)
      ? parentSnap.data().linkedChildren : [];
    const sd = studentSnap.data();
    const studentName = `${sd.firstName || ''} ${sd.lastName || ''}`.trim();
    if (existingLinked.includes(fresh.studentId)) {
      return { ok: false, reason: 'already-linked', studentName };
    }

    const studentUpdate = { parentIds: admin.firestore.FieldValue.arrayUnion(uid) };
    if (grantAccess) {
      studentUpdate.access = buildStudentAccess({
        academicYear: currentYear, source: 'book_pack_assumed', grantedBy: uid,
      });
    }
    tx.update(studentRef, studentUpdate);
    tx.set(parentRef, {
      linkedChildren: admin.firestore.FieldValue.arrayUnion(fresh.studentId),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    tx.update(codeRef, {
      status: 'used', usedBy: uid, usedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { ok: true, studentName, grantedAccess: grantAccess };
  });
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  initApp();
  const db = admin.firestore();
  const auth = admin.auth();
  const now = admin.firestore.FieldValue.serverTimestamp();

  process.stdout.write(`Setting up parent ${opts.email} in project ${PROJECT_ID}\n`);

  const resolved = await resolveParent(db, opts.email, opts.codes);
  if (!resolved) {
    die(`No parent record found for ${opts.email} and no link code resolved a school to create one in.`);
  }
  const { schoolId } = resolved;
  const fullName = opts.name || 'Parent';

  // 1. Auth user (reuse existing uid when the doc exists).
  const { uid, action } = await ensureAuthUser(auth, {
    uid: resolved.uid, email: opts.email, password: opts.password, fullName,
  });
  process.stdout.write(`  • Auth: ${action} (uid ${uid}, school ${schoolId})\n`);

  // 2. Parent doc — create a minimal one only if none existed; otherwise just
  //    force phoneVerified:false (frictionless email/password sign-in).
  const parentRef = db.collection('schools').doc(schoolId).collection('parents').doc(uid);
  if (!resolved.exists) {
    await parentRef.set({
      id: uid, email: opts.email, fullName, role: 'parent', schoolId,
      linkedChildren: [], isActive: true, createdAt: now,
      phoneVerified: false,
      relationshipLabel: opts.relationship || 'Parent',
      ...(opts.phone ? { phoneNumber: opts.phone } : {}),
    }, { merge: true });
    process.stdout.write('  • Parent doc: created\n');
  } else {
    await parentRef.set({ phoneVerified: false, isActive: true }, { merge: true });
    process.stdout.write('  • Parent doc: refreshed (phoneVerified=false)\n');
  }

  // 3. Email → school index.
  await db.collection('userSchoolIndex').doc(hashEmail(opts.email)).set(
    { email: opts.email, schoolId, userType: 'parent', userId: uid, updatedAt: now },
    { merge: true }
  );

  // 4. Redeem each link code.
  let linked = 0;
  for (const code of opts.codes) {
    try {
      const r = await redeemCode(db, uid, code);
      if (r.ok) {
        linked++;
        process.stdout.write(
          `  • Code ${code}: linked to ${r.studentName}` +
          `${r.grantedAccess ? ' (granted book-pack access)' : ''}\n`
        );
      } else if (r.reason === 'already-linked') {
        process.stdout.write(`  • Code ${code}: already linked to ${r.studentName} — skipped\n`);
      } else {
        process.stdout.write(`  • Code ${code}: NOT redeemed — ${r.reason}\n`);
      }
    } catch (e) {
      process.stdout.write(`  • Code ${code}: error — ${e.message}\n`);
    }
  }

  process.stdout.write(
    [
      '',
      `✓ Done. ${linked}/${opts.codes.length} code(s) redeemed.`,
      '',
      '  Sign in with email + password (no SMS/MFA challenge):',
      `    ${opts.email}  /  ${opts.password}`,
      '',
    ].join('\n')
  );
  process.exit(0);
}

main().catch((e) => die(`Setup failed: ${e.stack || e}`));
