#!/usr/bin/env node
// BREAK-GLASS: clear a super-admin's TOTP (MFA) enrollment so they can
// re-enroll on next login. This is the escape hatch for a lost authenticator
// when portal peer-reset isn't possible (e.g. you are the only super-admin).
//
// It only DELETES the adminMfa/{uid} document — it needs no decryption key, so
// it works even if ADMIN_MFA_ENC_KEY_AU is misconfigured.
//
// Runs with Application Default Credentials (the operator's gcloud login):
//   gcloud auth application-default login            # once
//   node admin/scripts/reset-admin-mfa.mjs --uid <UID> --dry-run   # check
//   node admin/scripts/reset-admin-mfa.mjs --uid <UID>             # apply
//
// Find your UID in the Firebase console (Authentication) or from the
// superAdmins collection.

import { initializeApp, applicationDefault } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

function arg(name) {
  const i = process.argv.indexOf(`--${name}`);
  return i !== -1 ? process.argv[i + 1] : undefined;
}

const uid = arg("uid");
const dryRun = process.argv.includes("--dry-run");
const project = process.env.PROJECT ?? "lumi-ninc-au";

if (!uid) {
  console.error("Usage: node admin/scripts/reset-admin-mfa.mjs --uid <UID> [--dry-run]");
  process.exit(2);
}

initializeApp({ credential: applicationDefault(), projectId: project });
const db = getFirestore();

async function main() {
  const ref = db.collection("adminMfa").doc(uid);
  const snap = await ref.get();
  if (!snap.exists) {
    console.log(`No adminMfa doc for ${uid} — nothing to reset (already unenrolled).`);
    return;
  }
  const enrolled = !!snap.data()?.secret;
  console.log(
    `${dryRun ? "[DRY RUN] " : ""}adminMfa/${uid} exists (enrolled: ${enrolled}).`,
  );
  if (dryRun) {
    console.log("Dry run — nothing deleted. Re-run without --dry-run to clear it.");
    return;
  }
  await ref.delete();
  console.log(`Deleted adminMfa/${uid}. They will be prompted to enrol on next login.`);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
