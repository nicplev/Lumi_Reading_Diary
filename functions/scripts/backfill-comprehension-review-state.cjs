#!/usr/bin/env node
/**
 * Normalises retained comprehension recordings into the shared teacher-inbox
 * review model.
 *
 * Safe default: this script is dry-run unless `--apply` is supplied. A valid
 * reviewed marker for the current object generation is preserved; every other
 * uploaded recording becomes `pending` and stale reviewer fields are cleared.
 *
 * Usage:
 *   node functions/scripts/backfill-comprehension-review-state.cjs
 *   node functions/scripts/backfill-comprehension-review-state.cjs --school ID
 *   node functions/scripts/backfill-comprehension-review-state.cjs --apply
 *
 * Optional:
 *   --project ID   Firebase project (default: lumi-ninc-au)
 *   --school ID    Limit to one school
 *   --apply        Persist changes (otherwise preview only)
 */
const admin = require("firebase-admin");

const args = process.argv.slice(2);
const valueAfter = (flag) => {
  const index = args.indexOf(flag);
  return index >= 0 ? args[index + 1] : undefined;
};

const projectId = valueAfter("--project") || "lumi-ninc-au";
const schoolId = valueAfter("--school");
const apply = args.includes("--apply");
const pageSize = 400;

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId,
});
const db = admin.firestore();
const {FieldPath, FieldValue} = admin.firestore;

function baseQuery() {
  const collection = schoolId ?
    db.collection("schools").doc(schoolId).collection("readingLogs") :
    db.collectionGroup("readingLogs");
  return collection
    .where("comprehensionAudioUploaded", "==", true)
    .orderBy(FieldPath.documentId());
}

async function run() {
  let cursor;
  let scanned = 0;
  let preserved = 0;
  let pending = 0;

  while (true) {
    let query = baseQuery().limit(pageSize);
    if (cursor) query = query.startAfter(cursor);
    const snapshot = await query.get();
    if (snapshot.empty) break;

    let batch = db.batch();
    let writes = 0;
    for (const doc of snapshot.docs) {
      scanned++;
      const data = doc.data();
      const generation = data.comprehensionAudioObjectGeneration;
      const validReviewed =
        data.comprehensionAudioReviewStatus === "reviewed" &&
        typeof generation === "string" &&
        generation.length > 0 &&
        data.comprehensionAudioReviewedGeneration === generation;
      if (validReviewed) {
        preserved++;
        continue;
      }

      pending++;
      console.log(`${apply ? "UPDATE" : "WOULD UPDATE"} ${doc.ref.path}`);
      if (apply) {
        batch.update(doc.ref, {
          comprehensionAudioReviewStatus: "pending",
          comprehensionAudioReviewedAt: FieldValue.delete(),
          comprehensionAudioReviewedGeneration: FieldValue.delete(),
        });
        writes++;
      }
    }
    if (apply && writes > 0) await batch.commit();
    cursor = snapshot.docs[snapshot.docs.length - 1];
    if (snapshot.size < pageSize) break;
  }

  console.log(JSON.stringify({
    mode: apply ? "applied" : "dry-run",
    projectId,
    schoolId: schoolId || "all",
    scanned,
    preserved,
    pending,
  }, null, 2));
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
