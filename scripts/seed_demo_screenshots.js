#!/usr/bin/env node
/**
 * App Store screenshot overlay for the demo school.
 *
 * Additive layer that runs AFTER scripts/seed_demo_school.js and dresses the
 * demo tenant for the approved shot list (docs/app-store/screenshots/):
 *
 *   1. A distinct character avatar on every student (base seed leaves them
 *      null → plain initials circles).
 *   2. Two curated book sets with real cover art:
 *        - "Bookshelf 9": iconic children's books (covers via Open Library,
 *          the same source BookMetadataResolver falls back to at runtime).
 *        - LLLL decodable readers for the teacher library shelf (covers from
 *          scripts/llll_product_images.json CDN URLs).
 *   3. A whole-class byTitle allocation ("This week's picks") so the parent
 *      Tonight card shows real covers.
 *   4. A week-scan allocation so the kiosk shows a part-filled progress bar
 *      (kiosk matches allocations where startDate == startOfWeek EXACTLY).
 *   5. Four colored reading groups covering every 3G student.
 *   6. Top Reader (gold) + Special award holders and class award settings.
 *   7. Ava's log titles rewritten to cycle the Bookshelf 9 (stats-neutral
 *      metadata merge — the isStatsNoopUpdate guard skips re-aggregation),
 *      plus unread-teacher-comment markers on her commented log.
 *   8. A few extra "today" logs for 3G so the teacher engagement ring and
 *      weekly chart look alive.
 *   9. Leo staged at 49 total nights with no log today, so a single live
 *      quick-log during capture produces the "Night 50" + badge celebration.
 *
 * Idempotent; only touches schools/lumi_demo_primary_school and refuses to
 * run unless that school doc has isDemo: true.
 *
 * Usage:
 *   FIREBASE_ADMIN_SERVICE_ACCOUNT_PATH=/abs/path/key.json \
 *   GOOGLE_CLOUD_PROJECT=lumi-ninc-au node scripts/seed_demo_screenshots.js
 */

process.env.TZ = process.env.TZ || 'Australia/Melbourne';

const path = require('path');
const fs = require('fs');

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

const saPath = process.env.FIREBASE_ADMIN_SERVICE_ACCOUNT_PATH;
if (saPath) {
  const sa = JSON.parse(fs.readFileSync(saPath, 'utf8'));
  admin.initializeApp({ credential: admin.credential.cert(sa) });
} else {
  admin.initializeApp();
}
const db = admin.firestore();

const SCHOOL_ID = 'lumi_demo_primary_school';
const CLASS_3G = 'demo_class_3g';
const schoolRef = db.collection('schools').doc(SCHOOL_ID);

// ── Character avatars (all 16 students; ids from the base seed) ──────────
const CHARACTERS = {
  demo_student_ava_nguyen: 'pink_lumi',
  demo_student_zoe_webb: 'purple_lumi',
  demo_student_oliver_taylor: 'lumi_ninja',
  demo_student_isla_okafor: 'yellow_cat',
  demo_student_noah_lin: 'lumi_pirate',
  demo_student_mia_carter: 'orange_penguin',
  demo_student_riley_thompson: 'pink_frog',
  demo_student_grace_patel: 'orange_wizard',
  demo_student_billy_martin: 'blue_tiger',
  demo_student_ruby_jones: 'lumi_cat',
  demo_student_leo_nguyen: 'blue_space',
  demo_student_charlie_brown: 'green_bear',
  demo_student_sofia_rossi: 'lumi_crown',
  demo_student_jack_wilson: 'lumi_shark',
  demo_student_amelia_singh: 'lumi_headphones',
  demo_student_harper_lee: 'green_dj',
};

// ── Bookshelf 9 — iconic children's books, covers verified on Open Library ──
const olCover = (isbn) => `https://covers.openlibrary.org/b/isbn/${isbn}-L.jpg`;
const BOOKSHELF_9 = [
  { slug: 'treehouse', title: 'The 26-Storey Treehouse', author: 'Andy Griffiths', isbn: '9781742611273', level: 'M' },
  { slug: 'matilda', title: 'Matilda', author: 'Roald Dahl', isbn: '9780142410370', level: 'P' },
  { slug: 'dogman', title: 'Dog Man Unleashed', author: 'Dav Pilkey', isbn: '9780545935203', level: 'L' },
  { slug: 'wimpy_kid', title: 'Diary of a Wimpy Kid', author: 'Jeff Kinney', isbn: '9780810993136', level: 'N' },
  { slug: 'gruffalo', title: 'The Gruffalo', author: 'Julia Donaldson', isbn: '9780333710937', level: 'J' },
  { slug: 'possum_magic', title: 'Possum Magic', author: 'Mem Fox', isbn: '9780152632243', level: 'K' },
  { slug: 'caterpillar', title: 'The Very Hungry Caterpillar', author: 'Eric Carle', isbn: '9780399226908', level: 'J' },
  { slug: 'charlottes_web', title: "Charlotte's Web", author: 'E. B. White', isbn: '9780064400558', level: 'P' },
  { slug: 'bfg', title: 'The BFG', author: 'Roald Dahl', isbn: '9780142410387', level: 'N' },
];

// Tonight-card picks (subset of the 9, matching the teacher comment's
// Treehouse reference).
const WEEK_PICKS = ['treehouse', 'dogman', 'gruffalo'];

// ── Teacher shelf — LLLL decodables that have real CDN cover URLs ─────────
const LLLL_JSON = path.join(__dirname, 'llll_product_images.json');
const LLLL_WANTED = [
  // Only entries with real CDN cover URLs in the JSON (Fluency Fun 1-6 lack them).
  { match: 'Fluency Fun 7:', title: "Fluency Fun 7: Danny's Assignment", stage: 'Stage 7' },
  { match: 'Fluency Fun 8:', title: 'Fluency Fun 8: Be Sensible', stage: 'Stage 7' },
  { matchExact: 'Little Learners, Big World Nonfiction Stage 1', title: 'Big World Nonfiction: Stage 1', stage: 'Stage 1' },
  { matchExact: 'Little Learners, Big World Nonfiction Stage 2', title: 'Big World Nonfiction: Stage 2', stage: 'Stage 2' },
  { matchExact: 'Little Learners, Big World Nonfiction Stage 3', title: 'Big World Nonfiction: Stage 3', stage: 'Stage 3' },
  { matchExact: 'Little Learners, Big World Nonfiction Stage 4', title: 'Big World Nonfiction: Stage 4', stage: 'Stage 4' },
  { matchExact: 'Little Learners, Big World Nonfiction Stage 4+', title: 'Big World Nonfiction: Stage 4+', stage: 'Stage 4+' },
  { matchExact: 'Little Learners, Big World Nonfiction Stage 5', title: 'Big World Nonfiction: Stage 5', stage: 'Stage 5' },
  { matchExact: 'Little Learners, Big World Nonfiction Stage 6', title: 'Big World Nonfiction: Stage 6', stage: 'Stage 6' },
];

// ── Reading groups: partition of all ten 3G students ─────────────────────
const READING_GROUPS = [
  { id: 'demo_group_red_rockets', name: 'Red Rockets', color: '#F44336', level: 'J', targetMinutes: 15, students: ['demo_student_riley_thompson', 'demo_student_ruby_jones'] },
  { id: 'demo_group_orange_comets', name: 'Orange Comets', color: '#FF9800', level: 'K', targetMinutes: 15, students: ['demo_student_noah_lin', 'demo_student_billy_martin'] },
  { id: 'demo_group_green_geckos', name: 'Green Geckos', color: '#4CAF50', level: 'L', targetMinutes: 20, students: ['demo_student_zoe_webb', 'demo_student_oliver_taylor', 'demo_student_grace_patel'] },
  { id: 'demo_group_blue_bandicoots', name: 'Blue Bandicoots', color: '#2196F3', level: 'N', targetMinutes: 25, students: ['demo_student_ava_nguyen', 'demo_student_mia_carter', 'demo_student_isla_okafor'] },
];

// Kiosk "scanned this week" — 5 students not featured in parent shots.
const KIOSK_SCANNED = [
  'demo_student_oliver_taylor',
  'demo_student_isla_okafor',
  'demo_student_noah_lin',
  'demo_student_mia_carter',
  'demo_student_grace_patel',
];

// Extra "today" logs so the teacher engagement ring looks alive.
const TODAY_READERS = [
  { id: 'demo_student_oliver_taylor', minutes: 22, book: 'Dog Man Unleashed' },
  { id: 'demo_student_isla_okafor', minutes: 18, book: 'Diary of a Wimpy Kid' },
  { id: 'demo_student_grace_patel', minutes: 25, book: 'The Gruffalo' },
  { id: 'demo_student_noah_lin', minutes: 15, book: 'Possum Magic' },
];

const normalizeTitle = (t) => t.trim().toLowerCase().replace(/\s+/g, ' ');
const ts = (d) => admin.firestore.Timestamp.fromDate(d);

function startOfWeekLocal(now) {
  const day = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const monday = new Date(day);
  monday.setDate(day.getDate() - ((day.getDay() + 6) % 7)); // Mon=0 shift
  return monday;
}

function localDateString(d) {
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const now = new Date();
  const school = await schoolRef.get();
  if (!school.exists || school.data().isDemo !== true) {
    throw new Error(`Refusing to run: ${SCHOOL_ID} missing or not isDemo:true. Run seed_demo_school.js first.`);
  }
  const classSnap = await schoolRef.collection('classes').doc(CLASS_3G).get();
  if (!classSnap.exists) throw new Error('demo_class_3g missing.');
  const teacherUid = (classSnap.data().teacherIds || [])[0];
  if (!teacherUid) throw new Error('3G has no teacher.');

  // 1 ── character avatars
  let stamped = 0;
  for (const [studentId, characterId] of Object.entries(CHARACTERS)) {
    await schoolRef.collection('students').doc(studentId)
      .set({ characterId }, { merge: true });
    stamped++;
  }
  console.log(`✓ characterId on ${stamped} students`);

  // 2 ── books (Bookshelf 9 + LLLL shelf)
  const bookIdBySlug = {};
  for (const b of BOOKSHELF_9) {
    const id = `demo_book_${b.slug}`;
    bookIdBySlug[b.slug] = id;
    await schoolRef.collection('books').doc(id).set({
      title: b.title,
      titleNormalized: normalizeTitle(b.title),
      author: b.author,
      isbn: b.isbn,
      coverImageUrl: olCover(b.isbn),
      readingLevel: b.level,
      genres: [],
      tags: ['demo'],
      isActive: true,
      createdAt: ts(new Date(now.getTime() - 21 * 864e5)),
      addedBy: teacherUid,
      source: 'seed_demo_screenshots',
    }, { merge: true });
  }
  console.log(`✓ ${BOOKSHELF_9.length} Bookshelf-9 books (Open Library covers)`);

  const llllItems = JSON.parse(fs.readFileSync(LLLL_JSON, 'utf8'));
  const llllList = Array.isArray(llllItems) ? llllItems : Object.values(llllItems);
  let shelf = 0;
  for (const [i, want] of LLLL_WANTED.entries()) {
    const hit = llllList.find((it) => {
      const name = it.name || '';
      if (want.matchExact) return name === want.matchExact;
      return name.startsWith(want.match);
    });
    const url = hit && (hit.cover_image_url || '').startsWith('http') ? hit.cover_image_url : null;
    if (!url) { console.log(`  ! no cover for "${want.title}" — skipped`); continue; }
    const isbn = hit.barcode && hit.barcode !== 'TBC' ? hit.barcode.replace(/-/g, '') : null;
    // First shelf book gets createdAt: now → the yellow NEW badge.
    const createdAt = shelf === 0 ? ts(now) : ts(new Date(now.getTime() - (10 + i) * 864e5));
    await schoolRef.collection('books').doc(`demo_book_llll_${i}`).set({
      title: want.title,
      titleNormalized: normalizeTitle(want.title),
      author: 'Little Learners Love Literacy',
      ...(isbn ? { isbn } : {}),
      coverImageUrl: url,
      readingLevel: want.stage,
      genres: [],
      tags: ['demo'],
      isActive: true,
      createdAt,
      addedBy: teacherUid,
      source: 'seed_demo_screenshots',
      metadata: { llllProductCode: hit.product_code || null, isDecodable: true },
    }, { merge: true });
    shelf++;
  }
  console.log(`✓ ${shelf} LLLL shelf books (CDN covers)`);

  // 3 ── whole-class byTitle allocation → Tonight card covers
  const picks = BOOKSHELF_9.filter((b) => WEEK_PICKS.includes(b.slug));
  await schoolRef.collection('allocations').doc('demo_alloc_3g_picks').set({
    schoolId: SCHOOL_ID,
    classId: CLASS_3G,
    teacherId: teacherUid,
    studentIds: [], // whole class → parent home's classAllocations query
    type: 'byTitle',
    cadence: 'daily',
    targetMinutes: 20,
    startDate: ts(new Date(now.getTime() - 7 * 864e5)),
    endDate: ts(new Date(now.getTime() + 21 * 864e5)),
    assignmentItems: picks.map((b) => ({
      id: `item_${b.slug}`,
      title: b.title,
      bookId: bookIdBySlug[b.slug],
      isbn: b.isbn,
      isDeleted: false,
      addedAt: ts(new Date(now.getTime() - 7 * 864e5)),
      addedBy: teacherUid,
    })),
    bookTitles: picks.map((b) => b.title),
    bookIds: picks.map((b) => bookIdBySlug[b.slug]),
    schemaVersion: 2,
    isRecurring: false,
    isActive: true,
    createdAt: ts(new Date(now.getTime() - 7 * 864e5)),
    createdBy: teacherUid,
  });
  console.log('✓ byTitle allocation "This week\'s picks" (3 covered titles)');

  // 4 ── kiosk week-scan allocation (startDate must EQUAL startOfWeek)
  const monday = startOfWeekLocal(now);
  await schoolRef.collection('allocations').doc('demo_alloc_3g_weekscan').set({
    schoolId: SCHOOL_ID,
    classId: CLASS_3G,
    teacherId: teacherUid,
    studentIds: KIOSK_SCANNED,
    type: 'byLevel',
    cadence: 'weekly',
    targetMinutes: 20,
    startDate: ts(monday),
    endDate: ts(new Date(monday.getTime() + 7 * 864e5)),
    levelStart: 'J',
    levelEnd: 'N',
    assignmentItems: [],
    schemaVersion: 2,
    isRecurring: false,
    isActive: true,
    createdAt: ts(monday),
    createdBy: teacherUid,
  });
  console.log(`✓ kiosk week-scan allocation (${KIOSK_SCANNED.length} scanned, week of ${localDateString(monday)})`);

  // 5 ── reading groups
  for (const [i, g] of READING_GROUPS.entries()) {
    await schoolRef.collection('readingGroups').doc(g.id).set({
      classId: CLASS_3G,
      schoolId: SCHOOL_ID,
      name: g.name,
      readingLevel: g.level,
      studentIds: g.students,
      color: g.color,
      targetMinutes: g.targetMinutes,
      createdAt: ts(new Date(now.getTime() - 14 * 864e5)),
      createdBy: teacherUid,
      isActive: true,
      sortOrder: i,
    }, { merge: true });
  }
  console.log(`✓ ${READING_GROUPS.length} reading groups (all 3G students grouped)`);

  // 6 ── awards: class settings + holders
  await schoolRef.collection('classes').doc(CLASS_3G).set({
    settings: { awards: { topReader: { enabled: true, name: 'Top Reader' } } },
  }, { merge: true });
  await schoolRef.collection('students').doc('demo_student_oliver_taylor').set({
    autoAward: {
      characterId: 'gold_lumi',
      name: 'Top Reader',
      weekOf: localDateString(monday),
      awardedAt: ts(monday),
    },
  }, { merge: true });
  await schoolRef.collection('students').doc('demo_student_isla_okafor').set({
    manualAward: {
      characterId: 'special_lumi',
      name: 'Star Helper',
      awardedAt: ts(new Date(now.getTime() - 2 * 864e5)),
      awardedBy: teacherUid,
    },
  }, { merge: true });
  console.log('✓ awards: Oliver holds gold Top Reader, Isla holds Special');

  // 7 ── Ava: retitle logs to cycle the Bookshelf 9 (stats-neutral merges;
  //      the isStatsNoopUpdate trigger guard skips re-aggregation), plus
  //      unread-comment markers on her commented log.
  const avaLogs = await schoolRef.collection('readingLogs')
    .where('studentId', '==', 'demo_student_ava_nguyen').get();
  const ordered = avaLogs.docs
    .sort((a, b) => a.data().date.toMillis() - b.data().date.toMillis());
  let batch = db.batch();
  let inBatch = 0;
  ordered.forEach((doc, i) => {
    batch.update(doc.ref, { bookTitles: [BOOKSHELF_9[i % BOOKSHELF_9.length].title] });
    if (++inBatch >= 400) { batch.commit(); batch = db.batch(); inBatch = 0; }
  });
  if (inBatch > 0) await batch.commit();
  console.log(`✓ retitled ${ordered.length} Ava logs across the Bookshelf 9`);

  const commented = avaLogs.docs.find((d) => d.data().teacherComment);
  if (commented) {
    await commented.ref.update({
      lastCommentAt: commented.data().commentedAt ?? ts(now),
      lastCommentByRole: 'teacher',
      commentsViewedAt: {},
    });
    console.log('✓ unread teacher-comment markers on Ava\'s commented log');
  } else {
    console.log('  ! no commented Ava log found — unread marker skipped');
  }

  // 8 ── extra "today" logs (skip students who already logged today)
  const dayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const students = await schoolRef.collection('students').get();
  const studentById = new Map(students.docs.map((d) => [d.id, d.data()]));
  let added = 0;
  for (const r of TODAY_READERS) {
    const existing = await schoolRef.collection('readingLogs')
      .where('studentId', '==', r.id)
      .where('date', '>=', ts(dayStart))
      .limit(1).get();
    if (!existing.empty) continue;
    const s = studentById.get(r.id);
    const parentId = (s.parentIds || [])[0] || teacherUid;
    const when = new Date(Math.min(now.getTime(), dayStart.getTime() + 8.5 * 36e5));
    await schoolRef.collection('readingLogs').doc(`demo_log_today_${r.id}`).set({
      studentId: r.id,
      parentId,
      schoolId: SCHOOL_ID,
      classId: CLASS_3G,
      date: ts(when),
      minutesRead: r.minutes,
      targetMinutes: 20,
      status: 'completed',
      bookTitles: [r.book],
      isOfflineCreated: false,
      createdAt: ts(when),
      childFeeling: 'happy',
      parentComment: null,
      parentCommentSelections: [],
      loggedByName: 'Parent',
      loggedByLabel: 'Parent',
    });
    added++;
  }
  console.log(`✓ ${added} extra today-logs for the engagement ring`);

  // 9 ── Leo staged one night before the 50-night badge. Delete any log he
  //      has today (celebration needs a fresh first-log-of-tonight), give
  //      the stats triggers a beat to settle, then pin his counters.
  const leoToday = await schoolRef.collection('readingLogs')
    .where('studentId', '==', 'demo_student_leo_nguyen')
    .where('date', '>=', ts(dayStart)).get();
  for (const doc of leoToday.docs) await doc.ref.delete();
  if (!leoToday.empty) {
    console.log(`  deleted ${leoToday.size} of Leo's today-logs; waiting for stats triggers…`);
    await sleep(15000);
  }
  const yesterday = new Date(dayStart.getTime() - 12 * 36e5); // yesterday 12:00
  await schoolRef.collection('students').doc('demo_student_leo_nguyen').set({
    stats: {
      totalReadingDays: 49,
      currentStreak: 11,
      lastReadingDate: ts(yesterday),
    },
  }, { merge: true });
  console.log('✓ Leo staged at 49 nights / 11-night streak (quick-log → "Night 50")');

  console.log('\nScreenshot overlay complete.');
}

main().then(() => process.exit(0)).catch((err) => {
  console.error(err);
  process.exit(1);
});
