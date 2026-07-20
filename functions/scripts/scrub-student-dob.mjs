#!/usr/bin/env node
// One-off: delete the stale `dateOfBirth` field from every student document.
//
// The field is no longer collected, written or read anywhere (removed across
// the shared type, both portals and the Flutter model). This scrubs the values
// already stored so no residual DOB remains — the strongest data-minimisation
// position for the ST4S assessment.
//
// Runs with Application Default Credentials (the operator's gcloud login):
//   gcloud auth application-default login   # once
//   node functions/scripts/scrub-student-dob.mjs --dry-run   # count only
//   node functions/scripts/scrub-student-dob.mjs             # apply
//
// Collection-group scans `students` across every school. Batched deletes of
// the single field via FieldValue.delete(); nothing else on the doc changes.
// Idempotent — re-running after a clean pass is a no-op.

import {initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore, FieldValue} from "firebase-admin/firestore";

const DRY_RUN = process.argv.includes("--dry-run");
const PROJECT = process.env.PROJECT ?? "lumi-ninc-au";
const BATCH_LIMIT = 400;

initializeApp({credential: applicationDefault(), projectId: PROJECT});
const db = getFirestore();

async function main() {
  console.log(
    `${DRY_RUN ? "[DRY RUN] " : ""}scanning students for dateOfBirth ` +
    `(project ${PROJECT})...`
  );
  const snap = await db.collectionGroup("students").get();

  let withDob = 0;
  let deleted = 0;
  let batch = db.batch();
  let pending = 0;

  for (const doc of snap.docs) {
    if (doc.get("dateOfBirth") === undefined) continue;
    withDob++;
    if (DRY_RUN) continue;
    batch.update(doc.ref, {dateOfBirth: FieldValue.delete()});
    pending++;
    if (pending >= BATCH_LIMIT) {
      await batch.commit();
      deleted += pending;
      console.log(`  committed ${deleted}...`);
      batch = db.batch();
      pending = 0;
    }
  }
  if (!DRY_RUN && pending > 0) {
    await batch.commit();
    deleted += pending;
  }

  console.log(
    `scanned ${snap.size} student docs; ` +
    `${withDob} carried dateOfBirth` +
    (DRY_RUN ? " (dry run — nothing changed)" : `; deleted from ${deleted}`)
  );
}

main().then(() => process.exit(0)).catch((err) => {
  console.error(err);
  process.exit(1);
});
