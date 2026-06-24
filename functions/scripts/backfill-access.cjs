#!/usr/bin/env node
/**
 * One-off access-model backfill (Admin SDK — bypasses client rules).
 *
 * Seeds the materialised access fields introduced by the licensing/lifecycle
 * work so existing data is consistent the moment enforcement goes live:
 *   1. `config/academicYear` — the single boundary source of truth (created
 *      only if missing).
 *   2. Each onboarded (isActive !== false) school gets a `schoolSubscriptions/
 *      {schoolId}_{year}` row (status from --sub-status, default `comp`) and
 *      `school.access = {status:'active', ...}`.
 *   3. Each student gets `student.access = {status:'active', academicYear,
 *      expiresAt, source}` where source is derived from enrollmentStatus
 *      (book_pack/direct_purchase -> their channel; otherwise book_pack_assumed,
 *      since onboarded-school students are presumed covered).
 *
 * Idempotent: re-running overwrites the same deterministic values. Only ever
 * GRANTS access — it never suspends — so it is safe to run before the cron and
 * rules ship.
 *
 * Reuses functions/src/access.ts (compiled to lib/access.js) for the boundary
 * math so the backfill can never drift from the live functions.
 *
 * ── Prereqs ──────────────────────────────────────────────────────────────────
 *   1. Build the functions so lib/ exists:
 *        npm --prefix functions run build
 *   2. Application Default Credentials with Firestore read/write:
 *        gcloud auth application-default login
 *
 * ── Usage ────────────────────────────────────────────────────────────────────
 *   # Preview a single school:
 *   node functions/scripts/backfill-access.cjs --school <id> --dry-run
 *   # Apply to one school:
 *   node functions/scripts/backfill-access.cjs --school <id>
 *   # Every school (careful):
 *   node functions/scripts/backfill-access.cjs --dry-run
 *
 * Flags:
 *   --project <id>      Firebase project        (default: lumi-ninc-au)
 *   --school  <id>      Limit to one school      (omit = every school)
 *   --year    <YYYY>    Academic year to seed    (default: derived from today)
 *   --sub-status <s>    School subscription seed  (default: comp)
 *   --dry-run           Print what would change; write nothing
 */
const path = require("path");
const admin = require("firebase-admin");

let access;
try {
  access = require(path.join(__dirname, "..", "lib", "access.js"));
} catch (err) {
  console.error(
    "Could not load lib/access.js — build the functions first:\n" +
    "  npm --prefix functions run build\n", err.message);
  process.exit(1);
}
const {academicYearForDate, hardExpiryFor, DEFAULT_TIMEZONE} = access;

const args = process.argv.slice(2);
const has = (f) => args.includes(f);
const val = (f) => {
  const i = args.indexOf(f);
  return i >= 0 ? args[i + 1] : undefined;
};

const PROJECT = val("--project") || "lumi-ninc-au";
const schoolArg = val("--school");
const subStatus = val("--sub-status") || "comp";
const dryRun = has("--dry-run");

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: PROJECT,
});
const db = admin.firestore();

const TZ = DEFAULT_TIMEZONE;
const YEAR = val("--year") ? Number(val("--year")) : academicYearForDate(new Date(), TZ);
const EXPIRES = hardExpiryFor(YEAR, TZ);

function sourceFromEnrollment(enrollmentStatus) {
  if (enrollmentStatus === "direct_purchase") return "parent_direct";
  if (enrollmentStatus === "book_pack") return "book_pack_assumed";
  // Onboarded-school students are presumed covered via the KAKA pack.
  return "book_pack_assumed";
}

async function ensureAcademicYearConfig() {
  const ref = db.collection("config").doc("academicYear");
  const snap = await ref.get();
  if (snap.exists) {
    console.log(`config/academicYear already exists (currentAcademicYear=${snap.data().currentAcademicYear}); leaving as-is.`);
    return;
  }
  const cfg = {
    currentAcademicYear: YEAR,
    rolloverDate: `${YEAR + 1}-01-25`,
    hardExpiry: EXPIRES.toISOString(),
    timezone: TZ,
  };
  console.log(`config/academicYear -> ${JSON.stringify(cfg)}`);
  if (!dryRun) await ref.set(cfg);
}

async function backfillSchool(schoolId) {
  const schoolSnap = await db.collection("schools").doc(schoolId).get();
  if (!schoolSnap.exists) return {students: 0, updated: 0};
  if (schoolSnap.data().isActive === false) {
    console.log(`  skipping offboarded school ${schoolId}`);
    return {students: 0, updated: 0};
  }

  // 1. Subscription row + school.access.
  const subId = `${schoolId}_${YEAR}`;
  console.log(`  schoolSubscriptions/${subId} -> status=${subStatus}; school.access=active`);
  if (!dryRun) {
    await db.collection("schoolSubscriptions").doc(subId).set({
      schoolId,
      academicYear: YEAR,
      status: subStatus,
      currency: "AUD",
      validFrom: schoolSnap.data().createdAt ?? admin.firestore.FieldValue.serverTimestamp(),
      validUntil: EXPIRES,
      notes: "Seeded by backfill-access.cjs",
      updatedBy: "backfill-access",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    await schoolSnap.ref.set({
      access: {
        status: "active",
        academicYear: YEAR,
        reason: "backfill",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    }, {merge: true});
  }

  // 2. Students -> student.access (chunked batches of 400).
  const studentDocs = (await db.collection(`schools/${schoolId}/students`).get()).docs;
  let updated = 0;
  for (let i = 0; i < studentDocs.length; i += 400) {
    const chunk = studentDocs.slice(i, i + 400);
    const batch = db.batch();
    for (const doc of chunk) {
      const source = sourceFromEnrollment(doc.data().enrollmentStatus);
      batch.set(doc.ref, {
        access: {
          status: "active",
          academicYear: YEAR,
          expiresAt: EXPIRES,
          source,
          grantedAt: admin.firestore.FieldValue.serverTimestamp(),
          grantedBy: "backfill-access",
        },
      }, {merge: true});
      updated++;
    }
    if (!dryRun) await batch.commit();
  }
  console.log(`  ${updated} student(s) granted access {year=${YEAR}, expires=${EXPIRES.toISOString()}}`);
  return {students: studentDocs.length, updated};
}

(async () => {
  console.log(
    `Backfill access — project=${PROJECT} year=${YEAR} expires=${EXPIRES.toISOString()}` +
    (dryRun ? " — DRY RUN (no writes)" : ""));

  await ensureAcademicYearConfig();

  let schoolIds;
  if (schoolArg) {
    schoolIds = [schoolArg];
  } else {
    schoolIds = (await db.collection("schools").get()).docs.map((d) => d.id);
    console.log(`No --school given; processing all ${schoolIds.length} schools.`);
  }

  const totals = {students: 0, updated: 0};
  for (const sid of schoolIds) {
    console.log(`\nSchool ${sid}:`);
    const r = await backfillSchool(sid);
    totals.students += r.students;
    totals.updated += r.updated;
  }

  console.log(
    `\n${dryRun ? "Would grant" : "Granted"} access to ${totals.updated} student(s) ` +
    `(scanned ${totals.students}).`);
  process.exit(0);
})().catch((err) => {
  console.error("Backfill failed:", err);
  process.exit(1);
});
