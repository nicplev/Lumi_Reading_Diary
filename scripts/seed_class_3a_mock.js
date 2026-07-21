#!/usr/bin/env node

/**
 * Seed mock reading logs for Beaumaris Primary School class 3A.
 *
 * Scope is deliberately narrow: only the 9 students in 3A that have NO linked
 * parent account. Those students are CSV-imported placeholders (their
 * `parentEmail` values are dummies like "aiden.parent@email.com") and they
 * carry zero reading history, so seeding them is purely additive and no real
 * family ever sees fabricated data for their own child. The 7 students with
 * linked guardians — and their 59 genuine test logs — are never touched.
 *
 * Logs are written as TEACHER-PROXY logs (`loggedByRole: "teacher"`). The
 * validateReadingLog trigger (functions/src/index.ts:2178) exempts those from
 * the guardian-link check, so they validate cleanly instead of landing as
 * `invalid` — which is what would happen if we wrote them as parent logs for
 * students who have no parent.
 *
 * Reversibility: every document is tagged `isMockSeed: true` with a batch id
 * and uses a `mockseed_` id prefix. Existing real logs use numeric-timestamp
 * ids, so the two sets can never collide. `--undo` deletes exactly the tagged
 * docs and nothing else. Stats/class dashboards recompute themselves on both
 * write and delete via aggregateStudentStats + maintainClassDailyReading +
 * updateClassStats, so no aggregate is hand-written here.
 *
 * Usage:
 *   node scripts/seed_class_3a_mock.js --dry-run     # print plan, no writes
 *   node scripts/seed_class_3a_mock.js --commit      # write
 *   node scripts/seed_class_3a_mock.js --undo        # remove seeded docs
 */

"use strict";

// Reading times are local "after school / evening" clock values; pin the
// process to the school's timezone so day-bucketing matches the app.
process.env.TZ = process.env.TZ || "Australia/Melbourne";

const path = require("path");
const admin = require(path.join(__dirname, "..", "functions", "node_modules", "firebase-admin"));

const PROJECT_ID = "lumi-ninc-au";
const SCHOOL_ID = "beaumaris_primary_school";
const CLASS_ID = "gfRpKvyNOABaYg2vVLCi";
const TEACHER_UID = "jDZv5jwrUdOiNbxe42OmU3r6byh2";
const TARGET_MINUTES = 20; // class defaultMinutesTarget
const BATCH_ID = "3a_mock_2026w29";

const argv = process.argv.slice(2);
const DRY_RUN = argv.includes("--dry-run");
const COMMIT = argv.includes("--commit");
const UNDO = argv.includes("--undo");

if (!DRY_RUN && !COMMIT && !UNDO) {
  console.error("Refusing to run without an explicit mode: --dry-run | --commit | --undo");
  process.exit(1);
}

// ─── Target students ────────────────────────────────────────────────────────
// The 9 parentless students in 3A. Each is re-verified against Firestore
// before any write; a student that has since gained a guardian is skipped.

const STUDENTS = [
  {id: "3q1vDqkHRISAyTLzSDWp", name: "Aiden Baker", profile: "steady"},
  {id: "79JHIU0AnhVEpOBrPTEG", name: "Ava Walker", profile: "strong"},
  {id: "99AwU2uyMMmuCaAqY7Dm", name: "Jane Smith", profile: "improving"},
  {id: "G0AYz4KhdxKjCXD9mHJe", name: "Mia Scott", profile: "strong"},
  {id: "LjhmIOFWqMlPssUTemm5", name: "Lucas Young", profile: "sporadic"},
  {id: "T8JKsCbv1dHYihXNBr6a", name: "Tom Brown", profile: "steady"},
  {id: "U775g9rXUfZ8FVavZqaE", name: "Noah Taylor", profile: "emerging"},
  {id: "c8CelE6eVVkdDpTkmJxm", name: "Harper Mitchell", profile: "improving"},
  {id: "wuzb9jrEzgzBU2MWutUn", name: "Liam Davis", profile: "sporadic"},
];

// ─── Books (drawn from the school's own library, Year 3 appropriate) ─────────

const BOOKS = {
  confident: [
    "Harry Potter and the Philosopher's Stone",
    "The Lightning Thief",
    "Matilda",
    "The BFG",
    "Charlie and the Chocolate Factory",
  ],
  developing: [
    "Diary of a Wimpy Kid",
    "Dog Man",
    "The Bad Guys",
    "Weirdo",
    "The magic Faraway Tree",
  ],
  emerging: [
    "Diary of a wombat",
    "Possum Magic",
    "Wombat Stew",
    "Pig the Pug",
    "The Gruffalo",
  ],
};

// Reading profiles drive how full each student's week looks, so the class
// dashboard shows a realistic spread rather than uniform data.
//   dayChance  — [lastWeek, thisWeek] probability of reading on a given day
//   minutes    — [min, max] session length
//   shelf      — which book tier they read from
const PROFILES = {
  strong: {dayChance: [0.9, 0.95], minutes: [22, 35], shelf: "confident", partialChance: 0.03},
  steady: {dayChance: [0.7, 0.75], minutes: [16, 26], shelf: "developing", partialChance: 0.08},
  improving: {dayChance: [0.35, 0.8], minutes: [12, 24], shelf: "developing", partialChance: 0.12},
  sporadic: {dayChance: [0.35, 0.4], minutes: [10, 18], shelf: "emerging", partialChance: 0.2},
  emerging: {dayChance: [0.5, 0.55], minutes: [8, 15], shelf: "emerging", partialChance: 0.25},
};

const FEELINGS = ["okay", "good", "good", "great", "great", "tricky"];

const TEACHER_NOTES = [
  "Read aloud during quiet reading.",
  "Good expression today.",
  "Needed some help with longer words.",
  "Confident with new vocabulary.",
  "Followed along with finger tracking.",
  null,
  null,
  null,
];

// ─── Deterministic PRNG ─────────────────────────────────────────────────────
// Seeded per student so re-running produces byte-identical data (the write is
// idempotent, and a re-run after an undo restores the same dataset).

function hashSeed(str) {
  let h = 1779033703 ^ str.length;
  for (let i = 0; i < str.length; i++) {
    h = Math.imul(h ^ str.charCodeAt(i), 3432918353);
    h = (h << 13) | (h >>> 19);
  }
  return h >>> 0;
}

function mulberry32(seed) {
  let a = seed;
  return function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// ─── Date window: Mon 13 Jul 2026 → Tue 21 Jul 2026 ─────────────────────────

function buildWindow() {
  const days = [];
  // Last week Mon–Sun, then this week Mon–today (Tue).
  for (let d = 13; d <= 21; d++) {
    const date = new Date(2026, 6, d); // month 6 = July
    days.push({
      date,
      key: `2026-07-${String(d).padStart(2, "0")}`,
      dow: date.getDay(), // 0 Sun … 6 Sat
      isThisWeek: d >= 20,
    });
  }
  return days;
}

function atTime(day, hour, minute) {
  const d = new Date(day.date);
  d.setHours(hour, minute, 0, 0);
  return d;
}

// ─── Plan builder ───────────────────────────────────────────────────────────

function buildPlan() {
  const window = buildWindow();
  const plan = [];

  for (const student of STUDENTS) {
    const cfg = PROFILES[student.profile];
    const rnd = mulberry32(hashSeed(student.id + BATCH_ID));
    const shelf = BOOKS[cfg.shelf];
    let book = shelf[Math.floor(rnd() * shelf.length)];

    for (const day of window) {
      const chance = day.isThisWeek ? cfg.dayChance[1] : cfg.dayChance[0];
      // Weekends read a little less often across every profile.
      const weekendPenalty = day.dow === 0 || day.dow === 6 ? 0.6 : 1;
      if (rnd() > chance * weekendPenalty) continue;

      // Move on to a new book every few sessions.
      if (rnd() > 0.7) book = shelf[Math.floor(rnd() * shelf.length)];

      const [lo, hi] = cfg.minutes;
      const minutes = lo + Math.floor(rnd() * (hi - lo + 1));
      const partial = rnd() < cfg.partialChance;
      const minutesRead = partial ? Math.max(1, Math.floor(minutes / 2)) : minutes;

      // Reading happens after school / early evening.
      const readAt = atTime(day, 16 + Math.floor(rnd() * 4), Math.floor(rnd() * 60));

      // Teacher records the diary on the next school day, so weekend reading
      // is logged the following Monday — mirrors how the class actually runs.
      let loggedAt = new Date(readAt);
      if (day.dow === 6) loggedAt = atTime({date: new Date(day.date.getTime() + 2 * 864e5)}, 9, 20);
      else if (day.dow === 0) loggedAt = atTime({date: new Date(day.date.getTime() + 1 * 864e5)}, 9, 20);

      plan.push({
        id: `mockseed_${student.id}_${day.key}`,
        studentId: student.id,
        studentName: student.name,
        dayKey: day.key,
        data: {
          studentId: student.id,
          parentId: TEACHER_UID, // teacher-proxy: exempt from guardian check
          loggedByRole: "teacher",
          loggedByName: null, // filled at write time from the teacher profile
          loggedByLabel: "Teacher",
          schoolId: SCHOOL_ID,
          classId: CLASS_ID,
          date: readAt,
          createdAt: loggedAt,
          minutesRead,
          targetMinutes: TARGET_MINUTES,
          status: partial ? "partial" : "completed",
          bookTitles: [book],
          childFeeling: FEELINGS[Math.floor(rnd() * FEELINGS.length)],
          notes: TEACHER_NOTES[Math.floor(rnd() * TEACHER_NOTES.length)],
          isOfflineCreated: false,
          allocationId: null,
          parentComment: null,
          parentCommentFreeText: null,
          parentCommentSelections: [],
          teacherComment: null,
          commentedAt: null,
          commentedBy: null,
          photoUrls: null,
          syncedAt: null,
          metadata: {source: "mock_seed"},
          comprehensionAudioUploaded: false,
          comprehensionAudioPath: null,
          comprehensionAudioDurationSec: null,
          // Reversibility markers.
          isMockSeed: true,
          mockSeedBatch: BATCH_ID,
        },
      });
    }
  }
  return plan;
}

// ─── Main ───────────────────────────────────────────────────────────────────

async function main() {
  const plan = buildPlan();

  if (DRY_RUN) {
    console.log(`PLAN — ${plan.length} reading logs across ${STUDENTS.length} students`);
    console.log(`Window: 2026-07-13 (Mon) → 2026-07-21 (Tue)  |  batch: ${BATCH_ID}\n`);
    const byStudent = {};
    for (const p of plan) {
      byStudent[p.studentName] = byStudent[p.studentName] || {days: [], mins: 0};
      byStudent[p.studentName].days.push(p.dayKey.slice(8));
      byStudent[p.studentName].mins += p.data.minutesRead;
    }
    for (const s of STUDENTS) {
      const b = byStudent[s.name] || {days: [], mins: 0};
      console.log(
        `${s.name.padEnd(16)} ${String(b.days.length).padStart(2)} sessions  ` +
        `${String(b.mins).padStart(3)} min  [${s.profile}]  days: ${b.days.join(",")}`
      );
    }
    console.log("\nNo writes performed (--dry-run).");
    return;
  }

  admin.initializeApp({projectId: PROJECT_ID});
  const db = admin.firestore();
  const logsRef = db.collection(`schools/${SCHOOL_ID}/readingLogs`);

  if (UNDO) {
    const snap = await logsRef
      .where("isMockSeed", "==", true)
      .where("mockSeedBatch", "==", BATCH_ID)
      .get();
    console.log(`Deleting ${snap.size} seeded logs (batch ${BATCH_ID})…`);
    let n = 0;
    for (const doc of snap.docs) {
      if (!doc.id.startsWith("mockseed_")) {
        console.warn(`  ! skipping unexpected id ${doc.id}`);
        continue;
      }
      await doc.ref.delete();
      n++;
      // Same spacing rationale as the write path: deletes fire the same
      // read-modify-write stats triggers and race the same way.
      await new Promise((r) => setTimeout(r, 1200));
    }
    console.log(`Deleted ${n}. Stats/class aggregates recompute via triggers.`);
    return;
  }

  // ── Safety re-verification before any write ──
  console.log("Verifying targets…");
  const teacher = await db.doc(`schools/${SCHOOL_ID}/users/${TEACHER_UID}`).get()
    .catch(() => null);
  const teacherName =
    (teacher && teacher.exists &&
      (teacher.data().displayName ||
        [teacher.data().firstName, teacher.data().lastName].filter(Boolean).join(" "))) ||
    "Class Teacher";

  const allowed = new Set();
  for (const s of STUDENTS) {
    const doc = await db.doc(`schools/${SCHOOL_ID}/students/${s.id}`).get();
    if (!doc.exists) {
      console.warn(`  ! ${s.name}: student doc missing — skipping`);
      continue;
    }
    const d = doc.data();
    if ((d.parentIds || []).length > 0) {
      console.warn(`  ! ${s.name}: now has a linked guardian — skipping (out of agreed scope)`);
      continue;
    }
    if (d.classId !== CLASS_ID) {
      console.warn(`  ! ${s.name}: no longer in 3A — skipping`);
      continue;
    }
    allowed.add(s.id);
  }
  console.log(`  ${allowed.size}/${STUDENTS.length} students cleared.`);

  // ── Collision check: never overwrite a real log on the same day ──
  const existing = await logsRef.where("classId", "==", CLASS_ID).get();
  const takenDays = new Set();
  for (const doc of existing.docs) {
    const v = doc.data();
    if (doc.id.startsWith("mockseed_")) continue; // our own prior run
    const dt = v.date && v.date.toDate ? v.date.toDate() : null;
    if (!dt) continue;
    const key = `${v.studentId}_${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, "0")}-${String(dt.getDate()).padStart(2, "0")}`;
    takenDays.add(key);
  }

  // Writes are spaced, NOT batched. aggregateStudentStats /
  // applyClassStatsDelta do a non-transactional read-modify-write of the
  // student and class docs (stats_aggregation.ts:329). A batch of logs for the
  // same student fires those triggers concurrently, they all read the same
  // stale stats, and increments are lost — the first run of this script
  // undercounted 5 of 9 students. Spacing the writes keeps one trigger per
  // student in flight at a time.
  const SPACING_MS = 1200;
  let written = 0;
  let skipped = 0;

  for (const p of plan) {
    if (!allowed.has(p.studentId)) { skipped++; continue; }
    if (takenDays.has(`${p.studentId}_${p.dayKey}`)) {
      console.log(`  ~ ${p.studentName} ${p.dayKey}: real log exists — skipping`);
      skipped++;
      continue;
    }
    const data = {...p.data, loggedByName: teacherName};
    await logsRef.doc(p.id).set(data);
    written++;
    process.stdout.write(`\r  wrote ${written}/${plan.length}…`);
    await new Promise((r) => setTimeout(r, SPACING_MS));
  }
  process.stdout.write("\n");

  console.log(`\nWrote ${written} logs, skipped ${skipped}.`);
  console.log("Triggers will recompute student stats, feelingsByDay and class dashboards.");
  console.log(`Undo any time: node scripts/seed_class_3a_mock.js --undo`);
}

main().then(() => process.exit(0)).catch((e) => {
  console.error("FATAL", e);
  process.exit(1);
});
