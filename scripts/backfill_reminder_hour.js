#!/usr/bin/env node
/**
 * Stamp the denormalized `reminderHour` field onto every parent doc.
 *
 * sendReadingReminders now queries `.where("reminderHour", "==", localHour)`
 * instead of reading every tokened parent every hour. Parents WITHOUT the
 * field are invisible to that query, so this backfill must run right after
 * the functions deploy that introduces the query — the syncParentReminderHour
 * trigger keeps docs in sync from then on (and covers newly created parents).
 *
 * The hour computation MUST match parseReminderHour in
 * functions/src/notification_helpers.ts exactly, including the historical
 * quirk that a "00:xx" (midnight) preference falls back to 19 (parseInt
 * yields a falsy 0). Bug-for-bug so the backfill can't change who gets
 * reminded at which hour.
 *
 * Dry-run by default; pass --apply to write. Paged reads, 400-doc batches.
 *
 * Usage (PRODUCTION lumi-ninc-au — run deliberately):
 *   GOOGLE_CLOUD_PROJECT=lumi-ninc-au node scripts/backfill_reminder_hour.js [--apply]
 */

const path = require('path');

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

admin.initializeApp();
const db = admin.firestore();

const APPLY = process.argv.includes('--apply');
const PAGE = 500;
const BATCH = 400;

// Mirror of functions/src/notification_helpers.ts parseReminderHour —
// keep in sync (see header comment).
function parseReminderHour(reminderTime) {
  if (typeof reminderTime !== 'string' || reminderTime.length === 0) return 19;
  return parseInt(reminderTime.split(':')[0], 10) || 19;
}

async function main() {
  console.log(`Backfill reminderHour ${APPLY ? '(APPLY)' : '(dry-run — pass --apply to write)'}`);
  const schools = await db.collection('schools').get();
  let scanned = 0;
  let stamped = 0;
  let alreadyCorrect = 0;

  for (const school of schools.docs) {
    const parentsCol = school.ref.collection('parents');
    let last = null;
    let batch = db.batch();
    let inBatch = 0;

    for (;;) {
      let q = parentsCol.orderBy(admin.firestore.FieldPath.documentId()).limit(PAGE);
      if (last) q = q.startAfter(last);
      const page = await q.get();
      if (page.empty) break;

      for (const doc of page.docs) {
        scanned++;
        const data = doc.data();
        const desired = parseReminderHour(data.preferences && data.preferences.reminderTime);
        if (data.reminderHour === desired) {
          alreadyCorrect++;
          continue;
        }
        stamped++;
        if (APPLY) {
          batch.update(doc.ref, { reminderHour: desired });
          inBatch++;
          if (inBatch >= BATCH) {
            await batch.commit();
            batch = db.batch();
            inBatch = 0;
          }
        }
      }
      last = page.docs[page.docs.length - 1].id;
      if (page.size < PAGE) break;
    }

    if (APPLY && inBatch > 0) await batch.commit();
    console.log(`  ${school.id}: done`);
  }

  console.log(`Scanned ${scanned} parents across ${schools.size} schools.`);
  console.log(`${APPLY ? 'Stamped' : 'Would stamp'} ${stamped}; already correct: ${alreadyCorrect}.`);
}

main().then(() => process.exit(0)).catch((err) => {
  console.error(err);
  process.exit(1);
});
