#!/usr/bin/env node
/**
 * Seed (or reset) the sales-demo school: "Lumi Demo Primary School".
 *
 * Creates a fully-populated, clearly-marked demo tenant so live demos never
 * start from an empty school: staff + parent accounts, classes, 16 students
 * with 60 days of reading logs, streaks, achievements, allocations, a
 * parent↔teacher comment thread, and active parent link codes.
 * See docs/demo-playbook.md for the demo flow this data is designed around.
 *
 * Usage:
 *   DEMO_PASSWORD='<secret from your password manager>' \
 *   FIREBASE_ADMIN_SERVICE_ACCOUNT_PATH=/abs/path/to/service-account.json \
 *     node scripts/seed_demo_school.js [--dry-run] [--reset] [--yes]
 *
 *   OR with Application Default Credentials:
 *     gcloud auth application-default login
 *     node scripts/seed_demo_school.js [flags]
 *
 * Flags:
 *   --dry-run   Print the full planned write-set and exit. Never connects to
 *               Firebase, so it works without credentials or node_modules
 *               network access. Run this first.
 *   --reset     Wipe the demo school (Auth users, index entries, link codes,
 *               school doc + all subcollections) and re-seed it fresh.
 *               Refuses to touch any school whose doc lacks `isDemo: true`.
 *   --yes       Skip the interactive project-id confirmation (CI/scripted).
 *
 * Dependency resolution: firebase-admin is not installed at the repo root
 * (pnpm monorepo). The script auto-falls-back to functions/node_modules, so:
 *   cd functions && npm install && cd .. && node scripts/seed_demo_school.js
 *
 * Idempotent: every document has a deterministic ID; re-running updates the
 * same docs in place. Log dates are derived from "today", so re-running on a
 * later day shifts the reading history window forward (run before each demo
 * day — or just run --reset, which is the recommended pre-demo ritual).
 *
 * Interaction with Cloud Functions triggers (safe, but know what fires):
 *   - validateReadingLog (onCreate readingLogs) checks minutes 1-240, that
 *     the student exists, and that the log's parentId is in the student's
 *     parentIds. Seeding order (students before logs) and the ghost-parent
 *     linking below are arranged so every seeded log validates.
 *   - aggregateStudentStats / class stats recompute from the logs on every
 *     log write. The stats this script writes are computed from the same
 *     seeded logs, so trigger recomputes converge to the same numbers
 *     (the weekly reconciler repairs any streak-tolerance nuance).
 *   - detectAchievements fires on student-doc *updates* only; initial seeding
 *     uses set(), and pre-earned achievement ids are deduped by the trigger,
 *     so badges are not double-awarded during live demo logging.
 *
 * Pre-demo checklist (also in docs/demo-playbook.md):
 *   1. node scripts/seed_demo_school.js --reset      (confirm project id!)
 *   2. Log into the school-admin portal as the demo admin — charts populated.
 *   3. Log into the app as demo teacher — class 3G shows last night's logs.
 *   4. Log into the app as demo parent — Ava's streak + badges visible.
 */

"use strict";

// Log timestamps use local-time setHours(); pin the process to the demo
// school's timezone so "7pm bedtime reading" is 7pm Melbourne on any host.
// Must run before the first Date operation (Node caches the tz lazily).
process.env.TZ = process.env.TZ || "Australia/Melbourne";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const readline = require("readline");

// ─── CLI ────────────────────────────────────────────────────────────────────

const argv = process.argv.slice(2);
const DRY_RUN = argv.includes("--dry-run");
const RESET = argv.includes("--reset");
const ASSUME_YES = argv.includes("--yes");
const KNOWN_FLAGS = new Set(["--dry-run", "--reset", "--yes"]);

for (const arg of argv) {
  if (!KNOWN_FLAGS.has(arg)) {
    die(`Unknown flag: ${arg}\nUsage: node scripts/seed_demo_school.js [--dry-run] [--reset] [--yes]`);
  }
}

function die(msg, code = 1) {
  process.stderr.write(`${msg}\n`);
  process.exit(code);
}

function log(msg) {
  process.stdout.write(`${msg}\n`);
}

// ─── Small utilities ────────────────────────────────────────────────────────

function sha256(s) {
  return crypto.createHash("sha256").update(s).digest("hex");
}

// userSchoolIndex doc ids are sha256(lowercased trimmed email) — must match
// lib/core/services/user_school_index_service.dart.
function emailHash(email) {
  return sha256(email.trim().toLowerCase());
}

// Deterministic PRNG so every run generates the same "random" data.
function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = mulberry32(0x10a11); // fixed seed → identical data every run
function pick(arr) {
  return arr[Math.floor(rand() * arr.length)];
}
function randInt(min, max) {
  return min + Math.floor(rand() * (max - min + 1));
}

// Same alphabet as ParentLinkingService._generateCode (no I, O, 1, 0).
const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
function linkCode() {
  let out = "";
  for (let i = 0; i < 8; i++) out += CODE_CHARS[Math.floor(rand() * CODE_CHARS.length)];
  return out;
}

// Mirrors functions/src/dateUtils.ts localDateString: en-CA renders YYYY-MM-DD.
function localDateString(date, tz) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: tz,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

function daysAgoAt(now, daysAgo, hour, minute) {
  const d = new Date(now.getTime() - daysAgo * 24 * 60 * 60 * 1000);
  d.setHours(hour, minute, 0, 0);
  return d;
}

// ─── The demo cast ──────────────────────────────────────────────────────────

const SCHOOL_ID = "lumi_demo_primary_school";
const TZ = "Australia/Melbourne";
const suppliedDemoPassword = process.env.DEMO_PASSWORD;
if (!DRY_RUN && (!suppliedDemoPassword || suppliedDemoPassword.length < 16)) {
  die(
    "DEMO_PASSWORD is required and must be at least 16 characters. " +
      "Load it from a password manager; no default password is stored in Git."
  );
}
const DEMO_PASSWORD = suppliedDemoPassword || "<dry-run-secret-not-loaded>";
const DEMO_EMAIL_DOMAIN = "lumidemo.school";

const SCHOOL_NAME = "Lumi Demo Primary School";

// Accounts shared with prospects on demo day. They live on @lumi-reading.com
// (plus-aliased into Nic's mailbox, so their Firebase password-reset emails are
// actually receivable — plus-addressing to this domain is proven working). Their
// passwords are rolled daily: the portal's "Provision today's demo password"
// issues the day password and scrambleDemoPasswords scrambles it nightly. The
// required DEMO_PASSWORD environment secret is only the initial value. Keep in sync with
// platformConfig/demoAccess (seedDemoAccessConfig) and functions/src/demo_access.ts.
const SHARED_ADMIN_EMAIL = "support+demo@lumi-reading.com";
const SHARED_TEACHER_EMAIL = "support+demo.teacher@lumi-reading.com";
const SHARED_PARENT_EMAIL = "support+demo.parent@lumi-reading.com";

// Old addresses the teacher/parent shared accounts used before the rename to
// @lumi-reading.com. Their userSchoolIndex hash entries are deleted every run
// so a stale entry can't shadow the new address (the Flutter app resolves school
// membership by emailHash(login email)). The Auth accounts themselves are
// renamed by uid — not recreated — so classes/logs/links stay intact.
const RETIRED_INDEX_EMAILS = [
  `demo.teacher@${DEMO_EMAIL_DOMAIN}`,
  `demo.parent@${DEMO_EMAIL_DOMAIN}`,
];

const STAFF = [
  {
    key: "admin",
    email: `demo.admin@${DEMO_EMAIL_DOMAIN}`,
    fullName: "Dana Whitfield",
    firstName: "Dana",
    lastName: "Whitfield",
    role: "schoolAdmin",
    classKeys: [],
    hasAuth: true,
  },
  {
    // Shared with prospects on demo day (the "Email demo details" admin login).
    // demo.admin above stays as the internal/backup admin, never shared.
    key: "sharedadmin",
    email: SHARED_ADMIN_EMAIL,
    fullName: "Jordan Ellis",
    firstName: "Jordan",
    lastName: "Ellis",
    role: "schoolAdmin",
    classKeys: [],
    hasAuth: true,
  },
  {
    // Shared demo TEACHER login. Renamed from demo.teacher@lumidemo.school.
    key: "teacher",
    email: SHARED_TEACHER_EMAIL,
    fullName: "Priya Sharma",
    firstName: "Priya",
    lastName: "Sharma",
    role: "teacher",
    classKeys: ["3g"],
    hasAuth: true,
  },
  {
    // Second teacher gives the staff list and class pages variety; nobody
    // logs in as him, so no Auth account is created.
    key: "teacher2",
    email: `demo.teacher2@${DEMO_EMAIL_DOMAIN}`,
    fullName: "Tom Rees",
    firstName: "Tom",
    lastName: "Rees",
    role: "teacher",
    classKeys: ["5b"],
    hasAuth: false,
  },
];

const PARENTS = [
  {
    // Shared demo PARENT login (mobile app only). Renamed from
    // demo.parent@lumidemo.school.
    key: "parent1",
    email: SHARED_PARENT_EMAIL,
    fullName: "Sarah Nguyen",
    relationshipLabel: "Mum",
    childKeys: ["ava", "leo"], // two children → shows the multi-child UI
    hasAuth: true,
  },
  {
    key: "parent2",
    email: `demo.parent2@${DEMO_EMAIL_DOMAIN}`,
    fullName: "Marcus Webb",
    relationshipLabel: "Dad",
    childKeys: ["zoe"],
    hasAuth: true,
  },
  // Ghost parents: Firestore docs only (no Auth). They exist so every student
  // with reading logs has a linked parent — validateReadingLog rejects logs
  // whose parentId is not in the student's parentIds.
  { key: "gp1", email: `jess.taylor@${DEMO_EMAIL_DOMAIN}`, fullName: "Jess Taylor", relationshipLabel: "Mum", childKeys: [], hasAuth: false },
  { key: "gp2", email: `dave.okafor@${DEMO_EMAIL_DOMAIN}`, fullName: "Dave Okafor", relationshipLabel: "Dad", childKeys: [], hasAuth: false },
  { key: "gp3", email: `mei.lin@${DEMO_EMAIL_DOMAIN}`, fullName: "Mei Lin", relationshipLabel: "Grandma", childKeys: [], hasAuth: false },
  { key: "gp4", email: `sam.carter@${DEMO_EMAIL_DOMAIN}`, fullName: "Sam Carter", relationshipLabel: "Dad", childKeys: [], hasAuth: false },
];

const CLASSES = [
  { key: "3g", id: "demo_class_3g", name: "3G Goannas", yearLevel: "Year 3", teacherKey: "teacher", defaultMinutesTarget: 20 },
  { key: "5b", id: "demo_class_5b", name: "5B Brolgas", yearLevel: "Year 5", teacherKey: "teacher2", defaultMinutesTarget: 25 },
];

const BOOKS_BY_LEVEL = {
  J: ["Billie B Brown: The Secret Message", "Hot Dog! Party Time", "The Very Cranky Bear", "Bluey: The Beach"],
  K: ["Zac Power: Poison Island", "Diary of a Wombat", "Possum Magic", "Dog Man Unleashed"],
  L: ["WeirDo", "The 13-Storey Treehouse", "Cat Kid Comic Club", "The Twits"],
  M: ["The 26-Storey Treehouse", "Charlotte's Web", "The BFG", "Fantastic Mr Fox"],
  N: ["Matilda", "The Witches", "Storm Boy", "James and the Giant Peach"],
  P: ["Wonder", "Harry Potter and the Philosopher's Stone", "Nevermoor", "The Wild Robot"],
};

// Reading pattern per student drives log generation across the last 60 days:
//   daily        — reads every single day (hero streak)
//   mostDays     — ~5-6 nights/week, streak of several trailing days
//   average      — ~4 nights/week
//   patchy       — ~2-3 nights/week, no current streak
//   lapsed       — read weeks 3-8, nothing in the last 14 days (at-risk)
//   none         — no logs at all (not yet onboarded)
const STUDENTS = [
  // ── 3G Goannas (Year 3) — the demo class ──
  { key: "ava", id: "demo_student_ava_nguyen", firstName: "Ava", lastName: "Nguyen", classKey: "3g", level: "M", pattern: "daily", parentKeys: ["parent1"], enrollmentStatus: "book_pack", hero: true },
  { key: "zoe", id: "demo_student_zoe_webb", firstName: "Zoe", lastName: "Webb", classKey: "3g", level: "L", pattern: "mostDays", parentKeys: ["parent2"], enrollmentStatus: "book_pack" },
  { key: "oliver", id: "demo_student_oliver_taylor", firstName: "Oliver", lastName: "Taylor", classKey: "3g", level: "L", pattern: "mostDays", parentKeys: ["gp1"], enrollmentStatus: "book_pack" },
  { key: "isla", id: "demo_student_isla_okafor", firstName: "Isla", lastName: "Okafor", classKey: "3g", level: "N", pattern: "average", parentKeys: ["gp2"], enrollmentStatus: "book_pack" },
  { key: "noah", id: "demo_student_noah_lin", firstName: "Noah", lastName: "Lin", classKey: "3g", level: "K", pattern: "average", parentKeys: ["gp3"], enrollmentStatus: "book_pack" },
  { key: "mia", id: "demo_student_mia_carter", firstName: "Mia", lastName: "Carter", classKey: "3g", level: "M", pattern: "patchy", parentKeys: ["gp4"], enrollmentStatus: "direct_purchase" },
  { key: "riley", id: "demo_student_riley_thompson", firstName: "Riley", lastName: "Thompson", classKey: "3g", level: "J", pattern: "lapsed", parentKeys: ["gp1"], enrollmentStatus: "book_pack", atRisk: true },
  { key: "grace", id: "demo_student_grace_patel", firstName: "Grace", lastName: "Patel", classKey: "3g", level: "L", pattern: "patchy", parentKeys: ["gp2"], enrollmentStatus: "book_pack" },
  // Not yet onboarded: no parent, no logs — populates the parent-links
  // funnel ("ready" / "no_subscription") and gives a live-linking target.
  { key: "billy", id: "demo_student_billy_martin", firstName: "Billy", lastName: "Martin", classKey: "3g", level: "K", pattern: "none", parentKeys: [], enrollmentStatus: "book_pack", linkTarget: true },
  { key: "ruby", id: "demo_student_ruby_jones", firstName: "Ruby", lastName: "Jones", classKey: "3g", level: "J", pattern: "none", parentKeys: [], enrollmentStatus: "not_enrolled" },

  // ── 5B Brolgas (Year 5) — depth for the admin view ──
  { key: "leo", id: "demo_student_leo_nguyen", firstName: "Leo", lastName: "Nguyen", classKey: "5b", level: "P", pattern: "average", parentKeys: ["parent1"], enrollmentStatus: "book_pack" },
  { key: "charlie", id: "demo_student_charlie_brown", firstName: "Charlie", lastName: "Brown", classKey: "5b", level: "N", pattern: "mostDays", parentKeys: ["gp3"], enrollmentStatus: "book_pack" },
  { key: "sofia", id: "demo_student_sofia_rossi", firstName: "Sofia", lastName: "Rossi", classKey: "5b", level: "P", pattern: "average", parentKeys: ["gp4"], enrollmentStatus: "book_pack" },
  { key: "jack", id: "demo_student_jack_wilson", firstName: "Jack", lastName: "Wilson", classKey: "5b", level: "N", pattern: "patchy", parentKeys: ["gp1"], enrollmentStatus: "direct_purchase" },
  { key: "amelia", id: "demo_student_amelia_singh", firstName: "Amelia", lastName: "Singh", classKey: "5b", level: "P", pattern: "mostDays", parentKeys: ["gp2"], enrollmentStatus: "book_pack" },
  { key: "harper", id: "demo_student_harper_lee", firstName: "Harper", lastName: "Lee", classKey: "5b", level: "N", pattern: "none", parentKeys: [], enrollmentStatus: "not_enrolled" },
];

const FEELINGS = ["okay", "good", "good", "great", "great", "tricky"];

const PARENT_COMMENTS = [
  "Read aloud together tonight.",
  "Sounded out the tricky words all by herself!",
  "A bit tired tonight but pushed through.",
  "Loved this chapter — didn't want to stop.",
  "Read to little brother as well.",
];

// Achievement tier metadata — mirrors BOOKS_TIERS / MINUTES_TIERS / DAYS_TIERS
// and DEFAULT_ACHIEVEMENT_THRESHOLDS in functions/src/index.ts. Streak tiers
// are intentionally not awarded there, so none are seeded here either.
const BOOK_TIERS = [
  { id: "books_t1", name: "Book Beginner", icon: "📖", rarity: "common", threshold: 5 },
  { id: "books_t2", name: "Book Collector", icon: "📚", rarity: "uncommon", threshold: 10 },
  { id: "books_t3", name: "Avid Reader", icon: "📗", rarity: "rare", threshold: 25 },
  { id: "books_t4", name: "Bookworm", icon: "🐛", rarity: "epic", threshold: 50 },
  { id: "books_t5", name: "Reading Legend", icon: "🏆", rarity: "legendary", threshold: 100 },
];
const MINUTE_TIERS = [
  { id: "minutes_t1", name: "Hour Hand", icon: "⏰", rarity: "common", threshold: 300 },
  { id: "minutes_t2", name: "Time Traveler", icon: "⌚", rarity: "uncommon", threshold: 600 },
  { id: "minutes_t3", name: "Marathon Reader", icon: "🏃", rarity: "rare", threshold: 1500 },
  { id: "minutes_t4", name: "Time Master", icon: "⏳", rarity: "epic", threshold: 3000 },
  { id: "minutes_t5", name: "Eternal Reader", icon: "♾️", rarity: "legendary", threshold: 6000 },
];
const DAY_TIERS = [
  { id: "days_t1", name: "Decade Reader", icon: "📅", rarity: "common", threshold: 10 },
  { id: "days_t2", name: "Fifty Nights", icon: "🌙", rarity: "rare", threshold: 50 },
  { id: "days_t3", name: "Century Reader", icon: "💯", rarity: "epic", threshold: 100 },
  { id: "days_t4", name: "Year of Reading", icon: "🏆", rarity: "legendary", threshold: 365 },
];

// ─── Log generation ─────────────────────────────────────────────────────────

const HISTORY_DAYS = 60;

// Which of the last HISTORY_DAYS days (0 = today) the student read on.
function readingDaysForPattern(pattern) {
  const days = [];
  for (let d = 0; d < HISTORY_DAYS; d++) {
    let reads = false;
    switch (pattern) {
      case "daily":
        // 40-day unbroken run ending yesterday (the streak continues live
        // when the parent logs tonight's reading during the demo), with a
        // believable ramp-up before that.
        reads = d >= 1 && (d <= 40 || rand() > 0.25);
        break;
      case "mostDays":
        // Unbroken trailing week, then ~5-6 nights/week with the odd miss.
        reads = d >= 1 && d <= 7 ? true : d > 7 && rand() > 0.2;
        break;
      case "average":
        reads = d >= 1 && (d <= 3 || rand() > 0.45);
        break;
      case "patchy":
        reads = d >= 1 && rand() > 0.65;
        break;
      case "lapsed":
        reads = d >= 14 && rand() > 0.35;
        break;
      case "none":
        reads = false;
        break;
      default:
        throw new Error(`Unknown pattern: ${pattern}`);
    }
    if (reads) days.push(d);
  }
  return days;
}

function buildLogsForStudent(student, cls, parent, now) {
  const logs = [];
  const books = BOOKS_BY_LEVEL[student.level];
  const days = readingDaysForPattern(student.pattern);
  let book = pick(books);

  for (const d of days) {
    // ~7pm local bedtime reading, jittered so timestamps aren't uniform.
    const date = daysAgoAt(now, d, 19, randInt(0, 50));
    // Every third-ish session moves on to a new book.
    if (rand() > 0.66) book = pick(books);
    const minutes = randInt(10, 28); // validateReadingLog requires 1-240
    const partial = rand() > 0.9;
    logs.push({
      id: `demo_log_${student.key}_${localDateString(date, TZ)}`,
      data: {
        studentId: student.id,
        parentId: parent.uid,
        schoolId: SCHOOL_ID,
        classId: cls.id,
        date,
        minutesRead: partial ? Math.max(1, Math.floor(minutes / 2)) : minutes,
        targetMinutes: cls.defaultMinutesTarget,
        status: partial ? "partial" : "completed",
        bookTitles: [book],
        isOfflineCreated: false,
        createdAt: date,
        childFeeling: pick(FEELINGS),
        parentComment: rand() > 0.75 ? pick(PARENT_COMMENTS) : null,
        parentCommentSelections: [],
        loggedByName: parent.fullName,
        loggedByLabel: parent.relationshipLabel,
        // Pre-marked valid; the validateReadingLog trigger re-stamps this
        // on create and reaches the same verdict.
        validationStatus: "valid",
      },
    });
  }
  return logs;
}

function computeStats(logs, now) {
  const dates = new Set();
  let totalMinutes = 0;
  let totalBooks = 0;
  let lastReadingDate = null;
  for (const { data } of logs) {
    totalMinutes += data.minutesRead;
    totalBooks += data.bookTitles.length;
    dates.add(localDateString(data.date, TZ));
    if (!lastReadingDate || data.date > lastReadingDate) lastReadingDate = data.date;
  }

  const has = (d) => dates.has(localDateString(daysAgoAt(now, d, 12, 0), TZ));

  // Trailing streak: consecutive days ending today or yesterday. This is the
  // strict version of the server's gentle streak (which also tolerates short
  // gaps), so it only ever under-reports; the stats triggers / weekly
  // reconciler recompute the canonical value from the same logs.
  let current = 0;
  for (let d = has(0) ? 0 : 1; has(d); d++) current++;

  let longest = 0;
  let run = 0;
  for (let d = HISTORY_DAYS; d >= 0; d--) {
    run = has(d) ? run + 1 : 0;
    if (run > longest) longest = run;
  }

  const inWindow = (n) => {
    let count = 0;
    for (let d = 0; d < n; d++) if (has(d)) count++;
    return count;
  };

  const totalReadingDays = dates.size;
  return {
    totalMinutesRead: totalMinutes,
    totalBooksRead: totalBooks,
    currentStreak: current,
    longestStreak: Math.max(longest, current),
    lastReadingDate,
    averageMinutesPerDay: totalReadingDays > 0 ? Math.round((totalMinutes / totalReadingDays) * 10) / 10 : 0,
    totalReadingDays,
    last30DaysCount: inWindow(30),
    last50DaysCount: inWindow(50),
    restDaysRemaining: current > 0 ? 2 : 0,
    readingDates: [...dates].sort(),
    lastUpdated: now,
  };
}

function buildAchievements(stats, student, now) {
  const out = [];
  // Backdate earnedAt to roughly when the cumulative stat crossed the tier
  // threshold, assuming steady accumulation across the seeded history.
  const earnedAtFor = (threshold, finalValue) => {
    const progress = Math.min(1, threshold / Math.max(finalValue, 1));
    const daysAgo = Math.round(HISTORY_DAYS * (1 - progress));
    return daysAgoAt(now, Math.max(daysAgo, 1), 19, 30);
  };

  if (stats.totalReadingDays >= 1) {
    out.push({
      id: "first_log",
      name: "First Chapter",
      description: "Logged your very first reading session!",
      icon: "📖",
      category: "special",
      rarity: "common",
      requirementType: "days",
      requiredValue: 1,
      earnedAt: daysAgoAt(now, HISTORY_DAYS - 1, 19, 30),
      displayed: true,
    });
  }
  const award = (tiers, category, requirementType, value, describe) => {
    for (const tier of tiers) {
      if (value < tier.threshold) break;
      out.push({
        id: tier.id,
        name: tier.name,
        description: describe(tier.threshold),
        icon: tier.icon,
        category,
        rarity: tier.rarity,
        requirementType,
        requiredValue: tier.threshold,
        earnedAt: earnedAtFor(tier.threshold, value),
        displayed: true,
      });
    }
  };
  award(BOOK_TIERS, "books", "books", stats.totalBooksRead, (v) => `Read ${v} books!`);
  award(MINUTE_TIERS, "minutes", "minutes", stats.totalMinutesRead, (v) => `Read for ${v / 60} hours total!`);
  award(DAY_TIERS, "readingDays", "days", stats.totalReadingDays, (v) => `Read on ${v} nights!`);

  // Scripted demo moment: the hero's newest badge is left un-displayed so the
  // celebration popup fires the first time the demo parent opens the app.
  if (student.hero && out.length > 0) {
    out.sort((a, b) => a.earnedAt - b.earnedAt);
    out[out.length - 1].displayed = false;
  }
  return out;
}

// ─── Plan assembly (pure — no Firebase) ─────────────────────────────────────

function buildPlan(now) {
  const plan = {
    authUsers: [], // {key, email, fullName, uid}
    school: null,
    users: [], // schools/{id}/users + top-level users mirror
    parents: [],
    classes: [],
    students: [],
    logs: [],
    comments: [],
    allocations: [],
    linkCodes: [],
    indexEntries: [],
  };

  // Deterministic UIDs for accounts we create through the Admin SDK. Auth
  // accepts custom uids on createUser; stable uids keep every Firestore
  // reference valid across re-seeds.
  const uidFor = (key) => `demo_${key}_${sha256(key).slice(0, 12)}`;

  const staffByKey = {};
  for (const s of STAFF) {
    staffByKey[s.key] = { ...s, uid: uidFor(s.key) };
    if (s.hasAuth) {
      plan.authUsers.push({ key: s.key, email: s.email, fullName: s.fullName, role: s.role, uid: uidFor(s.key) });
    }
  }
  const parentsByKey = {};
  for (const p of PARENTS) {
    parentsByKey[p.key] = { ...p, uid: uidFor(p.key) };
    if (p.hasAuth) {
      plan.authUsers.push({ key: p.key, email: p.email, fullName: p.fullName, role: "parent", uid: uidFor(p.key) });
    }
  }
  const classByKey = {};
  for (const c of CLASSES) classByKey[c.key] = c;
  const studentsByKey = {};
  for (const s of STUDENTS) studentsByKey[s.key] = s;

  const adminUid = staffByKey.admin.uid;
  const teacherUid = staffByKey.teacher.uid;

  // School
  const year = now.getFullYear();
  plan.school = {
    id: SCHOOL_ID,
    data: {
      name: SCHOOL_NAME,
      isDemo: true, // reset guard + "never a real tenant" marker
      // Keep the demo focused on reading habits and progress, not level labels.
      levelSchema: "none",
      termDates: {
        term1Start: new Date(`${year}-01-28T09:00:00+11:00`),
        term1End: new Date(`${year}-03-28T15:30:00+11:00`),
        term2Start: new Date(`${year}-04-14T09:00:00+10:00`),
        term2End: new Date(`${year}-06-26T15:30:00+10:00`),
        term3Start: new Date(`${year}-07-13T09:00:00+10:00`),
        term3End: new Date(`${year}-09-18T15:30:00+10:00`),
        term4Start: new Date(`${year}-10-05T09:00:00+11:00`),
        term4End: new Date(`${year}-12-18T15:30:00+11:00`),
      },
      quietHours: { start: "19:30", end: "07:00" },
      timezone: TZ,
      address: "1 Reading Lane, Melbourne VIC 3000",
      contactEmail: `office@${DEMO_EMAIL_DOMAIN}`,
      contactPhone: "(03) 9000 0000",
      isActive: true,
      createdAt: daysAgoAt(now, HISTORY_DAYS + 30, 9, 0),
      createdBy: adminUid,
      settings: { readingGoalMinutes: 20 },
      studentCount: STUDENTS.length,
      teacherCount: STAFF.filter((s) => s.role === "teacher").length,
      parentCount: PARENTS.length,
      subscriptionPlan: "demo",
    },
  };

  // Staff — written to schools/{id}/users AND mirrored to top-level users
  // (login reads the school subcollection; splash/userProvider reads the
  // top-level mirror — same dual-write the app's own setup utility does).
  for (const s of Object.values(staffByKey)) {
    const doc = {
      uid: s.uid,
      email: s.email,
      fullName: s.fullName,
      displayName: s.fullName,
      firstName: s.firstName,
      lastName: s.lastName,
      role: s.role,
      schoolId: SCHOOL_ID,
      schoolName: SCHOOL_NAME,
      linkedChildren: [],
      classIds: s.classKeys.map((k) => classByKey[k].id),
      isActive: true,
      isApproved: true,
      createdAt: daysAgoAt(now, HISTORY_DAYS + 20, 9, 0),
      updatedAt: now,
      lastLoginAt: now,
    };
    if (s.role === "schoolAdmin") {
      doc.permissions = {
        manageTeachers: true,
        manageStudents: true,
        manageClasses: true,
        viewReports: true,
        manageSchoolSettings: true,
      };
    }
    plan.users.push({ id: s.uid, data: doc });
    plan.indexEntries.push({
      id: emailHash(s.email),
      data: { email: s.email, schoolId: SCHOOL_ID, userType: "user", userId: s.uid, updatedAt: now },
    });
  }

  // Parents
  for (const p of Object.values(parentsByKey)) {
    plan.parents.push({
      id: p.uid,
      data: {
        email: p.email,
        fullName: p.fullName,
        role: "parent",
        schoolId: SCHOOL_ID,
        linkedChildren: [], // filled below once students are assembled
        relationshipLabel: p.relationshipLabel,
        isActive: true,
        createdAt: daysAgoAt(now, HISTORY_DAYS + 5, 18, 0),
      },
    });
    plan.indexEntries.push({
      id: emailHash(p.email),
      data: { email: p.email, schoolId: SCHOOL_ID, userType: "parent", userId: p.uid, updatedAt: now },
    });
  }
  const parentDocById = new Map(plan.parents.map((p) => [p.id, p.data]));

  // Students + their logs, stats, achievements
  const studentIdsByClass = { "3g": [], "5b": [] };
  const levelIndex = { J: 9, K: 10, L: 11, M: 12, N: 13, P: 15 }; // A=0 … Z=25

  for (const s of Object.values(studentsByKey)) {
    const cls = classByKey[s.classKey];
    studentIdsByClass[s.classKey].push(s.id);

    const linkedParents = s.parentKeys.map((k) => parentsByKey[k]);
    for (const lp of linkedParents) {
      const doc = parentDocById.get(lp.uid);
      if (!doc.linkedChildren.includes(s.id)) doc.linkedChildren.push(s.id);
    }

    const primaryParent = linkedParents[0] ?? null;
    const logs = primaryParent ? buildLogsForStudent(s, cls, primaryParent, now) : [];
    plan.logs.push(...logs);

    const stats = computeStats(logs, now);
    const achievements = buildAchievements(stats, s, now);

    const guardianProfiles = {};
    for (const lp of linkedParents) {
      guardianProfiles[lp.uid] = { name: lp.fullName, relationshipLabel: lp.relationshipLabel };
    }

    plan.students.push({
      id: s.id,
      key: s.key,
      data: {
        firstName: s.firstName,
        lastName: s.lastName,
        schoolId: SCHOOL_ID,
        classId: cls.id,
        currentReadingLevel: s.level,
        currentReadingLevelIndex: levelIndex[s.level],
        readingLevelUpdatedAt: daysAgoAt(now, 45, 10, 0),
        readingLevelUpdatedBy: teacherUid,
        readingLevelSource: "teacher",
        parentIds: linkedParents.map((lp) => lp.uid),
        isActive: true,
        createdAt: daysAgoAt(now, HISTORY_DAYS + 10, 9, 0),
        enrolledAt: daysAgoAt(now, HISTORY_DAYS + 10, 9, 0),
        enrollmentStatus: s.enrollmentStatus,
        levelHistory: [
          {
            level: s.level,
            changedAt: daysAgoAt(now, 45, 10, 0),
            changedBy: teacherUid,
            reason: "Term reading assessment",
          },
        ],
        guardianProfiles,
        achievements,
        stats,
      },
    });
  }

  // The killer demo moment: a live parent↔teacher thread on the hero's most
  // recent log (yesterday for the "daily" pattern).
  const heroLogs = plan.logs.filter((l) => l.id.startsWith("demo_log_ava_"));
  if (heroLogs.length > 0) {
    const latest = heroLogs.reduce((a, b) => (a.data.date > b.data.date ? a : b));
    const sarah = parentsByKey.parent1;
    // "This morning at 8:40" — clamped to now so it is never future-dated
    // when the seed runs before school hours.
    const thisMorning = new Date(Math.min(now.getTime(), daysAgoAt(now, 0, 8, 40).getTime()));
    latest.data.teacherComment = "Beautiful fluency this week, Ava — try the next Treehouse book!";
    latest.data.commentedAt = thisMorning;
    latest.data.commentedBy = teacherUid;
    plan.comments.push(
      {
        logId: latest.id,
        id: "demo_comment_1",
        data: {
          authorId: sarah.uid,
          authorRole: "parent",
          authorName: sarah.fullName,
          body: "She read the last chapter twice — couldn't put it down!",
          createdAt: daysAgoAt(now, 1, 19, 45),
          studentId: studentsByKey.ava.id,
          parentId: sarah.uid,
        },
      },
      {
        logId: latest.id,
        id: "demo_comment_2",
        data: {
          authorId: teacherUid,
          authorRole: "teacher",
          authorName: staffByKey.teacher.fullName,
          body: "Love to hear it! I've set the next book in her level — she's ready.",
          createdAt: thisMorning,
          studentId: studentsByKey.ava.id,
          parentId: sarah.uid,
        },
      }
    );
  }

  // Allocations for the demo class: one by-level, one weekend free-choice.
  plan.allocations.push(
    {
      id: "demo_alloc_3g_bylevel",
      data: {
        schoolId: SCHOOL_ID,
        classId: classByKey["3g"].id,
        teacherId: teacherUid,
        studentIds: studentIdsByClass["3g"],
        type: "byLevel",
        cadence: "daily",
        targetMinutes: 20,
        startDate: daysAgoAt(now, 30, 0, 0),
        endDate: daysAgoAt(now, -30, 0, 0), // 30 days into the future
        levelStart: "J",
        levelEnd: "N",
        assignmentItems: [],
        schemaVersion: 2,
        isRecurring: true,
        isActive: true,
        createdAt: daysAgoAt(now, 30, 8, 0),
        createdBy: teacherUid,
      },
    },
    {
      id: "demo_alloc_3g_freechoice",
      data: {
        schoolId: SCHOOL_ID,
        classId: classByKey["3g"].id,
        teacherId: teacherUid,
        studentIds: studentIdsByClass["3g"],
        type: "freeChoice",
        cadence: "weekly",
        targetMinutes: 30,
        startDate: daysAgoAt(now, 30, 0, 0),
        endDate: daysAgoAt(now, -30, 0, 0),
        assignmentItems: [],
        schemaVersion: 2,
        isRecurring: true,
        isActive: true,
        createdAt: daysAgoAt(now, 30, 8, 5),
        createdBy: teacherUid,
      },
    }
  );

  // Classes (studentIds now known)
  for (const c of CLASSES) {
    const teacher = staffByKey[c.teacherKey];
    plan.classes.push({
      id: c.id,
      data: {
        schoolId: SCHOOL_ID,
        name: c.name,
        yearLevel: c.yearLevel,
        teacherId: teacher.uid,
        teacherIds: [teacher.uid],
        studentIds: studentIdsByClass[c.key],
        defaultMinutesTarget: c.defaultMinutesTarget,
        isActive: true,
        createdAt: daysAgoAt(now, HISTORY_DAYS + 15, 9, 0),
        createdBy: adminUid,
      },
    });
  }

  // Active link codes for the un-linked students — printed/handed out during
  // in-person demos so a prospect can link "their" child live.
  for (const s of STUDENTS.filter((st) => st.parentKeys.length === 0)) {
    plan.linkCodes.push({
      id: `demo_code_${s.key}`,
      data: {
        studentId: s.id,
        schoolId: SCHOOL_ID,
        code: linkCode(),
        status: "active",
        createdAt: now,
        expiresAt: daysAgoAt(now, -365, 0, 0),
        createdBy: adminUid,
        intendedFor: "staff_issued",
      },
    });
  }

  return plan;
}

// ─── Dry run ────────────────────────────────────────────────────────────────

function printDryRun(plan) {
  const show = (obj) => JSON.stringify(obj, null, 2);
  log("── DRY RUN — nothing will be written ─────────────────────────────");
  log(`School doc:            schools/${SCHOOL_ID}  (isDemo: true)`);
  log(`Auth users:            ${plan.authUsers.length}  (password loaded from DEMO_PASSWORD)`);
  for (const u of plan.authUsers) log(`   • ${u.email}  uid=${u.uid}`);
  log(`Staff docs:            ${plan.users.length} (schools/${SCHOOL_ID}/users + top-level users mirror)`);
  log(`Parent docs:           ${plan.parents.length} (schools/${SCHOOL_ID}/parents)`);
  log(`userSchoolIndex docs:  ${plan.indexEntries.length}`);
  log(`Classes:               ${plan.classes.map((c) => c.data.name).join(", ")}`);
  log(`Students:              ${plan.students.length}`);
  for (const s of plan.students) {
    const st = s.data.stats;
    log(
      `   • ${s.data.firstName} ${s.data.lastName}  level=${s.data.currentReadingLevel}` +
        `  streak=${st.currentStreak}  days=${st.totalReadingDays}  mins=${st.totalMinutesRead}` +
        `  badges=${s.data.achievements.length}  status=${s.data.enrollmentStatus}`
    );
  }
  log(`Reading logs:          ${plan.logs.length} (last ${HISTORY_DAYS} days)`);
  log(`Log comments:          ${plan.comments.length} (thread on the hero's latest log)`);
  log(`Allocations:           ${plan.allocations.length}`);
  log(`Link codes:            ${plan.linkCodes.map((c) => `${c.data.code} → ${c.data.studentId}`).join(", ")}`);
  log("");
  log("Sample student doc (hero):");
  const hero = plan.students.find((s) => s.key === "ava");
  log(show({ ...hero.data, achievements: `[${hero.data.achievements.length} badges]`, stats: hero.data.stats }));
  log("");
  log("Sample reading log:");
  log(show(plan.logs[plan.logs.length - 1].data));
  log("───────────────────────────────────────────────────────────────────");
}

// ─── Firebase plumbing ──────────────────────────────────────────────────────

// firebase-admin isn't hoisted to the repo root (pnpm); fall back to the
// functions workspace where it is a direct dependency.
function loadFirebaseAdmin() {
  try {
    return require("firebase-admin");
  } catch (_) {
    try {
      return require(path.join(__dirname, "..", "functions", "node_modules", "firebase-admin"));
    } catch (_) {
      die(
        "Could not resolve firebase-admin. Install the functions dependencies first:\n" +
          "  cd functions && npm install\n" +
          "then re-run this script from the repo root."
      );
    }
  }
}

function initAdmin(admin) {
  const saPath = process.env.FIREBASE_ADMIN_SERVICE_ACCOUNT_PATH;
  if (saPath) {
    if (!fs.existsSync(saPath)) die(`Service account file not found at ${saPath}`);
    const sa = JSON.parse(fs.readFileSync(saPath, "utf-8"));
    admin.initializeApp({ credential: admin.credential.cert(sa) });
    return sa.project_id;
  }
  admin.initializeApp(); // GOOGLE_APPLICATION_CREDENTIALS / gcloud ADC
  const app = admin.app();
  return (
    app.options.projectId ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    process.env.GCLOUD_PROJECT ||
    "(unknown — check your ADC)"
  );
}

async function confirm(projectId, mode) {
  log("───────────────────────────────────────────────────────────────────");
  log(`  Firebase project : ${projectId}`);
  log(`  Mode             : ${mode}`);
  log(`  Target school    : schools/${SCHOOL_ID} ("${SCHOOL_NAME}")`);
  log("───────────────────────────────────────────────────────────────────");
  if (ASSUME_YES) return;
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const answer = await new Promise((resolve) => rl.question("Proceed? Type 'yes' to continue: ", resolve));
  rl.close();
  if (answer.trim().toLowerCase() !== "yes") die("Aborted — nothing written.", 0);
}

// ─── Reset ──────────────────────────────────────────────────────────────────

async function resetDemoSchool(admin, db, plan) {
  const schoolRef = db.collection("schools").doc(SCHOOL_ID);
  const snap = await schoolRef.get();

  if (snap.exists && snap.data().isDemo !== true) {
    die(
      `SAFETY STOP: schools/${SCHOOL_ID} exists but does not have isDemo: true.\n` +
        "Refusing to delete a school that is not marked as demo data."
    );
  }

  if (snap.exists) {
    log("Deleting demo school document tree (subcollections included)…");
    // recursiveDelete (firebase-admin ≥ 10.1) removes the doc and every
    // nested subcollection, including readingLogs/{id}/comments.
    if (typeof db.recursiveDelete === "function") {
      await db.recursiveDelete(schoolRef);
    } else {
      die("This firebase-admin version lacks recursiveDelete; upgrade functions/node_modules (needs >= 10.1).");
    }
  } else {
    log("No existing demo school doc — skipping tree delete.");
  }

  // Top-level artifacts that live outside the school tree.
  log("Deleting demo link codes…");
  const codes = await db.collection("studentLinkCodes").where("schoolId", "==", SCHOOL_ID).get();
  for (const doc of codes.docs) await doc.ref.delete();

  log("Deleting demo userSchoolIndex entries + top-level user mirrors…");
  for (const entry of plan.indexEntries) {
    await db.collection("userSchoolIndex").doc(entry.id).delete();
  }
  for (const user of plan.users) {
    await db.collection("users").doc(user.id).delete();
  }

  log("Deleting demo Auth users…");
  for (const u of plan.authUsers) {
    try {
      const existing = await admin.auth().getUserByEmail(u.email);
      await admin.auth().deleteUser(existing.uid);
      log(`   • deleted ${u.email}`);
    } catch (err) {
      if (err.code !== "auth/user-not-found") throw err;
    }
  }
  log("Reset complete.\n");
}

// ─── Seed ───────────────────────────────────────────────────────────────────

async function ensureAuthUsers(admin, plan) {
  log("Ensuring Auth users (emailVerified, no MFA — demo accounts must log in friction-free)…");
  for (const u of plan.authUsers) {
    let authUser;
    try {
      const existing = await admin.auth().getUserByEmail(u.email);
      if (existing.uid !== u.uid) {
        throw new Error(
          `SAFETY STOP: ${u.email} belongs to unexpected uid ${existing.uid}; ` +
          `expected ${u.uid}. Refusing to delete or repurpose an Auth user.`
        );
      }
      authUser = await admin.auth().updateUser(u.uid, {
        password: DEMO_PASSWORD,
        emailVerified: true,
        displayName: u.fullName,
        // A non-reset seed must also remove any factor accidentally enrolled
        // during rehearsal; otherwise the documented friction-free login is
        // not deterministic.
        multiFactor: { enrolledFactors: [] },
      });
      log(`   • exists   ${u.email}`);
    } catch (err) {
      if (err.code !== "auth/user-not-found") throw err;

      // The target email is free. Rename a known deterministic demo uid in
      // place so class, log and child references remain intact; otherwise
      // create the account for the first time.
      let existingByUid = null;
      try {
        existingByUid = await admin.auth().getUser(u.uid);
      } catch (lookupErr) {
        if (lookupErr.code !== "auth/user-not-found") throw lookupErr;
      }

      if (existingByUid) {
        const previousEmail = existingByUid.email || "";
        const knownDemoEmail =
          previousEmail.endsWith(`@${DEMO_EMAIL_DOMAIN}`) ||
          /^support\+demo(?:\.[^@]+)?@lumi-reading\.com$/.test(previousEmail);
        if (!knownDemoEmail) {
          throw new Error(
            `SAFETY STOP: deterministic demo uid ${u.uid} has unexpected email ` +
            `${previousEmail}; refusing to repurpose it.`
          );
        }
        authUser = await admin.auth().updateUser(u.uid, {
          email: u.email,
          password: DEMO_PASSWORD,
          emailVerified: true,
          displayName: u.fullName,
          multiFactor: { enrolledFactors: [] },
        });
        log(`   • renamed  ${previousEmail} → ${u.email}`);
      } else {
        authUser = await admin.auth().createUser({
          uid: u.uid,
          email: u.email,
          password: DEMO_PASSWORD,
          emailVerified: true,
          displayName: u.fullName,
        });
        log(`   • created  ${u.email}`);
      }
    }

    const claims = {
      ...(authUser.customClaims || {}),
      demoAccount: true,
      demoSchoolId: SCHOOL_ID,
    };
    if (u.role === "schoolAdmin") {
      // Demo administrators need an exception to the portal's
      // mandatory TOTP policy. The exemption is coupled to read-only claims
      // enforced by middleware, Firestore rules, and callable guards.
      claims.demoAdminMfaExempt = true;
      claims.demoReadOnly = true;
    } else {
      delete claims.demoAdminMfaExempt;
      delete claims.demoReadOnly;
    }
    await admin.auth().setCustomUserClaims(u.uid, claims);
  }
}

async function seedFirestore(db, plan) {
  const writer = db.bulkWriter();
  let count = 0;
  const set = (ref, data) => {
    writer.set(ref, data);
    count++;
  };

  const schoolRef = db.collection("schools").doc(SCHOOL_ID);
  set(schoolRef, plan.school.data);

  // Students must exist before their logs: validateReadingLog fires on log
  // create and checks the student doc + parent linkage.
  for (const u of plan.users) {
    set(schoolRef.collection("users").doc(u.id), u.data);
    set(db.collection("users").doc(u.id), u.data);
  }
  for (const p of plan.parents) set(schoolRef.collection("parents").doc(p.id), p.data);
  for (const c of plan.classes) set(schoolRef.collection("classes").doc(c.id), c.data);
  for (const s of plan.students) set(schoolRef.collection("students").doc(s.id), s.data);
  for (const a of plan.allocations) set(schoolRef.collection("allocations").doc(a.id), a.data);
  await writer.flush();

  for (const l of plan.logs) set(schoolRef.collection("readingLogs").doc(l.id), l.data);
  for (const c of plan.comments) {
    set(schoolRef.collection("readingLogs").doc(c.logId).collection("comments").doc(c.id), c.data);
  }
  for (const code of plan.linkCodes) set(db.collection("studentLinkCodes").doc(code.id), code.data);
  for (const entry of plan.indexEntries) set(db.collection("userSchoolIndex").doc(entry.id), entry.data);

  await writer.close();
  return count;
}

// Delete userSchoolIndex entries for addresses the shared accounts no longer
// use (post-rename), so a stale hash can't shadow the new address. Idempotent —
// a missing doc delete is a no-op.
async function cleanupRetiredIndexEntries(db) {
  for (const email of RETIRED_INDEX_EMAILS) {
    await db.collection("userSchoolIndex").doc(emailHash(email)).delete();
  }
  if (RETIRED_INDEX_EMAILS.length > 0) {
    log(`   • cleaned ${RETIRED_INDEX_EMAILS.length} retired userSchoolIndex entries`);
  }
}

// Write platformConfig/demoAccess — the non-secret config the demo-access
// backend + portal read. Idempotent, and PRESERVES any appStoreUrl/playStoreUrl
// an operator has filled in (those are set in the portal/console once the store
// listings are live — a re-seed must never clobber them back to null).
async function seedDemoAccessConfig(db) {
  const ref = db.collection("platformConfig").doc("demoAccess");
  const snap = await ref.get();
  const existing = snap.exists ? snap.data() : {};
  await ref.set({
    schoolId: SCHOOL_ID,
    adminEmail: SHARED_ADMIN_EMAIL,
    teacherEmail: SHARED_TEACHER_EMAIL,
    parentEmail: SHARED_PARENT_EMAIL,
    // Rotated nightly but never shared with prospects: the internal/backup admin
    // and the no-login second teacher/parent personas. Keeps every account in
    // the school off a known password.
    scrambleOnlyEmails: [
      `demo.admin@${DEMO_EMAIL_DOMAIN}`,
      `demo.teacher2@${DEMO_EMAIL_DOMAIN}`,
      `demo.parent2@${DEMO_EMAIL_DOMAIN}`,
    ],
    portalLoginUrl: "https://lumi-school-admin-au.web.app/login",
    marketingUrl: "https://lumi-reading.com",
    appStoreUrl: existing.appStoreUrl ?? null,
    playStoreUrl: existing.playStoreUrl ?? null,
    updatedAt: new Date(),
    updatedBy: "seed_demo_school.js",
  });
  const preserved = existing.appStoreUrl || existing.playStoreUrl;
  log(`   • platformConfig/demoAccess written (store URLs ${preserved ? "preserved" : "null"})`);
}

// ─── Main ───────────────────────────────────────────────────────────────────

async function main() {
  const now = new Date();
  const plan = buildPlan(now);

  if (DRY_RUN) {
    printDryRun(plan);
    return;
  }

  const admin = loadFirebaseAdmin();
  const projectId = initAdmin(admin);
  await confirm(projectId, RESET ? "RESET (wipe + re-seed)" : "seed / upsert");

  const db = admin.firestore();

  if (RESET) {
    await resetDemoSchool(admin, db, plan);
  } else {
    // Even outside --reset, never silently overwrite a non-demo school.
    const snap = await db.collection("schools").doc(SCHOOL_ID).get();
    if (snap.exists && snap.data().isDemo !== true) {
      die(`SAFETY STOP: schools/${SCHOOL_ID} exists without isDemo: true — refusing to overwrite.`);
    }
  }

  await ensureAuthUsers(admin, plan);
  log("Writing Firestore documents…");
  const written = await seedFirestore(db, plan);
  await cleanupRetiredIndexEntries(db);
  await seedDemoAccessConfig(db);

  log("");
  log(`✓ Demo school seeded (${written} documents).`);
  log("");
  log("  Demo logins:");
  for (const u of plan.authUsers) log(`    ${u.email}`);
  log("");
  log("  Passwords are ROLLED DAILY. The DEMO_PASSWORD secret is only the seed value —");
  log("  scrambleDemoPasswords scrambles it nightly, and the super-admin portal's");
  log("  \"Provision today's demo password\" issues the shared day password.");
  log("");
  log("  Live-linking codes (hand these out in demos):");
  for (const c of plan.linkCodes) log(`    ${c.data.code}  →  ${c.data.studentId}`);
  log("");
  log("  Next: run the pre-demo checks in docs/demo-playbook.md.");
}

main().catch((err) => die(`Seed failed: ${err.stack || err}`));
