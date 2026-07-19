import { createHash } from "node:crypto";

// Pure deterministic data builder mechanically extracted from the original
// CLI seed. Keep Firebase/Auth/deletion concerns in reseed.ts; this module has
// no credentials, network calls or environment-secret access.

function sha256(s) {
  return createHash("sha256").update(s).digest("hex");
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
let rand = mulberry32(0x10a11); // fixed seed → identical data every run
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

const DEMO_EMAIL_DOMAIN = "lumidemo.school";

const SCHOOL_ID = "lumi_demo_primary_school";
const TZ = "Australia/Melbourne";
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

// Canonical demo-school feature defaults. The super-admin demo control panel
// may change these during a provisioned day; the next fenced reseed restores
// this colourful, fully populated baseline.
export const DEMO_CONTROL_DEFAULTS = {
  audioRecordingEnabled: false,
  parentCommentsEnabled: true,
  freeTextCommentsEnabled: true,
  messagingEnabled: true,
  quickLoggingEnabled: true,
  commentPresets: [
    { id: "default-1", name: "Encouragement", chips: ["Great job!", "Keep it up!", "Loved hearing you read!", "So proud of you!"] },
    { id: "default-2", name: "Reading Skills", chips: ["Sounded out words well", "Good finger tracking", "Read with expression", "Used picture clues"] },
    { id: "default-3", name: "Comprehension", chips: ["Understood the story well", "Asked great questions", "Made predictions", "Retold the story"] },
  ],
};

// One selectable Lumi per seeded child. Keep this explicit and deterministic
// so every class/family surface has visual variety after every reseed.
export const DEMO_STUDENT_CHARACTER_IDS = [
  "pink_lumi",
  "blue_lumi",
  "green_lumi",
  "yellow_lumi",
  "orange_lumi",
  "purple_lumi",
  "light_blue_lumi",
  "lumi_chef",
  "lumi_cool_kid",
  "lumi_crown",
  "lumi_headphones",
  "lumi_ninja",
  "lumi_pirate",
  "lumi_space",
  "lumi_wizard",
  "lumi_shark",
];

if (DEMO_STUDENT_CHARACTER_IDS.length !== STUDENTS.length) {
  throw new Error("Every seeded demo student must have one distinct Lumi character.");
}

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
    books: [],
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
      settings: {
        readingGoalMinutes: 20,
        messaging: { enabled: DEMO_CONTROL_DEFAULTS.messagingEnabled },
        parentComments: {
          enabled: DEMO_CONTROL_DEFAULTS.parentCommentsEnabled,
          freeTextEnabled: DEMO_CONTROL_DEFAULTS.freeTextCommentsEnabled,
          customPresets: DEMO_CONTROL_DEFAULTS.commentPresets.map((category) => ({
            ...category,
            chips: [...category.chips],
          })),
        },
        // Shared demo accounts cannot upload new audio. Super-admin demo
        // controls can expose this local record/playback preview without
        // fabricating a real school's authority evidence.
        comprehensionRecording: {
          enabled: DEMO_CONTROL_DEFAULTS.audioRecordingEnabled,
          demoPreviewOnly: true,
        },
        quickLogging: { enabled: DEMO_CONTROL_DEFAULTS.quickLoggingEnabled },
      },
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

  for (const [studentIndex, s] of Object.values(studentsByKey).entries()) {
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
        characterId: DEMO_STUDENT_CHARACTER_IDS[studentIndex],
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
        access: {
          status: "active",
          academicYear: year,
          expiresAt: new Date(`${year}-12-31T23:59:59+11:00`),
          source: "demo_seed",
          grantedAt: now,
          grantedBy: "seed_demo_school",
        },
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

  // School-local books and a realistic by-title allocation. ISBNs are stable
  // published editions, verified against Australian publisher catalogues on
  // 17 July 2026. Demo data never writes the global community catalogue.
  const allocatedBooks = [
    { isbn: "9781742612379", title: "The 39-Storey Treehouse", author: "Andy Griffiths", publisher: "Pan Australia" },
    { isbn: "9781741699920", title: "The Very Cranky Bear", author: "Nick Bland", publisher: "Scholastic Press" },
    { isbn: "9780399255373", title: "The Day the Crayons Quit", author: "Drew Daywalt", publisher: "Philomel Books" },
  ];
  for (const book of allocatedBooks) {
    plan.books.push({
      id: `isbn_${book.isbn}`,
      data: {
        schoolId: SCHOOL_ID,
        title: book.title,
        titleNormalized: book.title.toLowerCase(),
        author: book.author,
        isbn: book.isbn,
        isbnNormalized: book.isbn,
        publisher: book.publisher,
        genres: [],
        tags: ["demo"],
        isActive: true,
        createdAt: daysAgoAt(now, 21, 9, 0),
        addedBy: teacherUid,
        scannedByTeacherIds: [teacherUid],
        timesAssignedSchoolWide: 1,
        source: "demo_seed",
      },
    });
  }

  // Allocations for the demo class: real titles plus weekend free-choice.
  plan.allocations.push(
    {
      id: "demo_alloc_3g_bytitle",
      data: {
        schoolId: SCHOOL_ID,
        classId: classByKey["3g"].id,
        teacherId: teacherUid,
        studentIds: studentIdsByClass["3g"],
        type: "byTitle",
        cadence: "weekly",
        targetMinutes: 20,
        startDate: daysAgoAt(now, 30, 0, 0),
        endDate: daysAgoAt(now, -30, 0, 0), // 30 days into the future
        assignmentItems: allocatedBooks.map((book, index) => ({
          id: `demo_item_${index + 1}`,
          title: book.title,
          bookId: `isbn_${book.isbn}`,
          isbn: book.isbn,
          isbnNormalized: book.isbn,
          isDeleted: false,
          addedAt: daysAgoAt(now, 7, 8, 0),
          addedBy: teacherUid,
          metadata: { source: "demo_seed" },
        })),
        bookTitles: allocatedBooks.map((book) => book.title),
        bookIds: allocatedBooks.map((book) => `isbn_${book.isbn}`),
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



export function buildDemoSchoolPlanData(now = new Date()) {
  // buildPlan used to run once per CLI process. Reset the deterministic PRNG
  // for every server invocation so retries produce the identical document set.
  rand = mulberry32(0x10a11);
  return buildPlan(now);
}

export const DEMO_SCHOOL_CONSTANTS = {
  schoolId: SCHOOL_ID,
  schoolName: SCHOOL_NAME,
  timezone: TZ,
  retiredIndexEmails: [...RETIRED_INDEX_EMAILS],
};
