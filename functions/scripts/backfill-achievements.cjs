#!/usr/bin/env node
/**
 * One-off achievements backfill (Admin SDK — bypasses the callable's auth).
 *
 * Awards every achievement each student currently qualifies for, based on their
 * existing stats, WITHOUT notifications. Idempotent and safe to re-run. Use it
 * to award students who already met thresholds before the fixed detector went
 * live — the deployed `detectAchievements` self-heals on each student's NEXT
 * stats update, but this awards them right now without waiting for a log.
 *
 * Reuses the exact same evaluation as the Cloud Functions
 * (`functions/src/achievements.ts` -> `lib/achievements.js`), so it can never
 * drift from the live awarding logic.
 *
 * ── Prereqs ──────────────────────────────────────────────────────────────────
 *   1. Build the functions so `lib/` exists:
 *        npm --prefix functions run build
 *   2. Application Default Credentials with Firestore access to the project:
 *        gcloud auth application-default login
 *      (the principal needs Firestore read/write on the target project)
 *
 * ── Usage ────────────────────────────────────────────────────────────────────
 *   # Preview a single student (recommended first — e.g. the test student):
 *   node functions/scripts/backfill-achievements.cjs --school <schoolId> --student <studentId> --dry-run
 *
 *   # Apply to that student:
 *   node functions/scripts/backfill-achievements.cjs --school <schoolId> --student <studentId>
 *
 *   # Whole school:
 *   node functions/scripts/backfill-achievements.cjs --school <schoolId>
 *
 *   # Every school (careful):
 *   node functions/scripts/backfill-achievements.cjs --dry-run
 *
 * Flags:
 *   --project <id>   Firebase project   (default: lumi-ninc-au)
 *   --school  <id>   Limit to one school (omit = every school)
 *   --student <id>   Limit to one student (requires --school)
 *   --dry-run        Print what would be awarded; write nothing
 */
const path = require("path");
const admin = require("firebase-admin");

let achievements;
try {
  achievements = require(path.join(__dirname, "..", "lib", "achievements.js"));
} catch (err) {
  console.error(
    "Could not load lib/achievements.js — build the functions first:\n" +
    "  npm --prefix functions run build\n", err.message);
  process.exit(1);
}
const {computeAwardableAchievements, DEFAULT_ACHIEVEMENT_THRESHOLDS} = achievements;

const args = process.argv.slice(2);
const has = (f) => args.includes(f);
const val = (f) => {
  const i = args.indexOf(f);
  return i >= 0 ? args[i + 1] : undefined;
};

const PROJECT = val("--project") || "lumi-ninc-au";
const schoolArg = val("--school");
const studentArg = val("--student");
const dryRun = has("--dry-run");

if (studentArg && !schoolArg) {
  console.error("--student requires --school");
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: PROJECT,
});
const db = admin.firestore();

async function resolveThresholds(schoolId) {
  let custom = {};
  try {
    const doc = await db.collection("schools").doc(schoolId).get();
    custom = (doc.data() || {}).settings?.achievementThresholds || {};
  } catch (_) {
    /* fall back to platform defaults */
  }
  return {
    streak: custom.streak || DEFAULT_ACHIEVEMENT_THRESHOLDS.streak,
    books: custom.books || DEFAULT_ACHIEVEMENT_THRESHOLDS.books,
    minutes: custom.minutes || DEFAULT_ACHIEVEMENT_THRESHOLDS.minutes,
    readingDays: custom.readingDays || DEFAULT_ACHIEVEMENT_THRESHOLDS.readingDays,
  };
}

async function backfillSchool(schoolId) {
  const thresholds = await resolveThresholds(schoolId);
  let docs;
  if (studentArg) {
    const d = await db.doc(`schools/${schoolId}/students/${studentArg}`).get();
    docs = d.exists ? [d] : [];
  } else {
    docs = (await db.collection(`schools/${schoolId}/students`).get()).docs;
  }

  let updated = 0;
  let badges = 0;
  for (const doc of docs) {
    const data = doc.data() || {};
    const stats = data.stats || {};
    const earnedIds = new Set((data.achievements || []).map((a) => a.id));
    const awardable = computeAwardableAchievements(stats, earnedIds, thresholds);
    if (awardable.length === 0) continue;

    const toAward = awardable.map((a) => ({
      ...a, earnedAt: admin.firestore.Timestamp.now(),
    }));
    console.log(
      `  ${data.firstName || doc.id} (${doc.id}): +` +
      toAward.map((a) => a.id).join(", "));

    if (!dryRun) {
      await doc.ref.update({
        achievements: admin.firestore.FieldValue.arrayUnion(...toAward),
      });
    }
    updated++;
    badges += toAward.length;
  }
  return {students: docs.length, updated, badges};
}

(async () => {
  console.log(
    `Backfill achievements — project=${PROJECT}` +
    (dryRun ? " — DRY RUN (no writes)" : ""));

  let schoolIds;
  if (schoolArg) {
    schoolIds = [schoolArg];
  } else {
    schoolIds = (await db.collection("schools").get()).docs.map((d) => d.id);
    console.log(`No --school given; processing all ${schoolIds.length} schools.`);
  }

  const totals = {students: 0, updated: 0, badges: 0};
  for (const sid of schoolIds) {
    console.log(`\nSchool ${sid}:`);
    const r = await backfillSchool(sid);
    totals.students += r.students;
    totals.updated += r.updated;
    totals.badges += r.badges;
  }

  console.log(
    `\n${dryRun ? "Would award" : "Awarded"}: ${totals.badges} badge(s) ` +
    `across ${totals.updated} student(s) (scanned ${totals.students}).`);
  process.exit(0);
})().catch((err) => {
  console.error("Backfill failed:", err);
  process.exit(1);
});
