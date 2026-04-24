#!/usr/bin/env node
/**
 * Seed a super-admin entry into Firestore.
 *
 * Writes to /superAdmins/{uid} which is the canonical allowlist consulted by
 * the impersonation Cloud Functions in functions/src/super_admin.ts (and by
 * any future server-side check). Clients are denied read/write; only the
 * Admin SDK (here or inside Cloud Functions) may touch this collection.
 *
 * Usage:
 *   FIREBASE_ADMIN_SERVICE_ACCOUNT_PATH=/abs/path/to/service-account.json \
 *     node scripts/seed_super_admin.js <uid> [email]
 *
 *   OR: use Application Default Credentials
 *     gcloud auth application-default login
 *     node scripts/seed_super_admin.js <uid> [email]
 *
 * Idempotent: rerunning with the same UID just updates the `updatedAt`
 * timestamp and merges the optional email.
 */

const admin = require("firebase-admin");
const fs = require("fs");

function die(msg, code = 1) {
  process.stderr.write(`${msg}\n`);
  process.exit(code);
}

function main() {
  const [, , uid, email] = process.argv;
  if (!uid || uid.startsWith("-")) {
    die(
      "Usage: node scripts/seed_super_admin.js <uid> [email]\n" +
        "  <uid>   Firebase Auth UID of the super-admin to allowlist.\n" +
        "  [email] Optional email for human-readable audit context."
    );
  }

  const saPath = process.env.FIREBASE_ADMIN_SERVICE_ACCOUNT_PATH;
  if (saPath) {
    if (!fs.existsSync(saPath)) {
      die(`Service account file not found at ${saPath}`);
    }
    admin.initializeApp({
      credential: admin.credential.cert(
        JSON.parse(fs.readFileSync(saPath, "utf-8"))
      ),
    });
  } else {
    // Falls back to GOOGLE_APPLICATION_CREDENTIALS or metadata-server ADC.
    admin.initializeApp();
  }

  const db = admin.firestore();
  const ref = db.collection("superAdmins").doc(uid);

  ref
    .set(
      {
        uid,
        email: email ?? null,
        grantedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    )
    .then(() => {
      process.stdout.write(
        `✓ Seeded superAdmins/${uid}${email ? ` (${email})` : ""}\n` +
          "  This user can now revoke impersonation sessions and export the\n" +
          "  impersonation audit trail from lumi-admin, and pass the\n" +
          "  Cloud Function super-admin check in requireSuperAdminAuth.\n"
      );
      process.exit(0);
    })
    .catch((err) => {
      die(`Failed to write superAdmins/${uid}: ${err.message ?? err}`);
    });
}

main();
