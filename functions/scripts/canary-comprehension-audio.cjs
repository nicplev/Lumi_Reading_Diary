#!/usr/bin/env node
/**
 * Destructive-but-contained production canary for the comprehension-audio
 * validation pipeline. It creates a synthetic parent and tenant, briefly
 * enables recording, invokes the real callable and isolated decoder, verifies
 * the canonical receipt, and removes every canary resource in a finally block.
 *
 * Usage:
 *   node functions/scripts/canary-comprehension-audio.cjs \
 *     --project lumi-ninc-au --confirm-production
 */
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const admin = require("firebase-admin");

const args = process.argv.slice(2);
const value = (flag) => {
  const index = args.indexOf(flag);
  return index >= 0 ? args[index + 1] : undefined;
};
const projectId = value("--project") || "lumi-ninc-au";
if (!args.includes("--confirm-production")) {
  console.error("Refusing to run without --confirm-production");
  process.exit(2);
}
if (projectId !== "lumi-ninc-au") {
  console.error(`Unexpected project: ${projectId}`);
  process.exit(2);
}

const repoRoot = path.resolve(__dirname, "..", "..");
const firebaseOptions = fs.readFileSync(
  path.join(repoRoot, "lib", "firebase_options.dart"),
  "utf8"
);
const webOptions = firebaseOptions.match(
  /static const FirebaseOptions web = FirebaseOptions\(([\s\S]*?)\n  \);/
)?.[1];
const apiKey = webOptions?.match(/apiKey: '([^']+)'/)?.[1];
if (!apiKey) throw new Error("Firebase Web API key was not found");

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId,
  storageBucket: `${projectId}.firebasestorage.app`,
});

const db = admin.firestore();
const bucket = admin.storage().bucket();
const auth = admin.auth();
const suffix = `${Date.now()}_${crypto.randomBytes(4).toString("hex")}`;
const schoolId = `security_audio_canary_${suffix}`;
const studentId = `student_${suffix}`;
const classId = `class_${suffix}`;
const logId = `log_${suffix}`;
const flagRef = db.doc("platformConfig/comprehensionRecording");
const schoolRef = db.doc(`schools/${schoolId}`);
const logRef = db.doc(`schools/${schoolId}/readingLogs/${logId}`);
const pendingPath = `comprehension_audio_uploads/${schoolId}/${logId}.m4a`;
const canonicalPath = `schools/${schoolId}/comprehension_audio/${logId}.m4a`;
let uid;
let originalFlag;
let canaryEmail;
let canaryPassword;

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function signInCanaryUser() {
  const response = await fetch(
    "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword" +
      `?key=${encodeURIComponent(apiKey)}`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        origin: "https://lumi-ninc-au.web.app",
        referer: "https://lumi-ninc-au.web.app/",
      },
      body: JSON.stringify({
        email: canaryEmail,
        password: canaryPassword,
        returnSecureToken: true,
      }),
    }
  );
  const body = await response.json();
  assert(
    response.ok,
    `Token exchange failed (${response.status}): ${body.error?.message || "unknown"}`
  );
  return body.idToken;
}

async function callConfirm(idToken) {
  const url = `https://australia-southeast1-${projectId}.cloudfunctions.net/` +
    "confirmComprehensionAudioUpload";
  const response = await fetch(url, {
    method: "POST",
    headers: {
      authorization: `Bearer ${idToken}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({data: {schoolId, logId, durationSec: 1}}),
  });
  const body = await response.json();
  assert(response.ok, `Callable failed (${response.status}): ${JSON.stringify(body)}`);
  return body.result;
}

async function cleanup() {
  await Promise.allSettled([
    bucket.file(pendingPath).delete({ignoreNotFound: true}),
    bucket.file(canonicalPath).delete({ignoreNotFound: true}),
  ]);
  if (uid) {
    const rateKey = crypto.createHash("sha256").update(uid).digest("hex");
    await db.doc(`backendRateLimits/audioValidation_${rateKey}`).delete();
    await auth.deleteUser(uid).catch((error) => {
      if (error.code !== "auth/user-not-found") throw error;
    });
  }
  await db.recursiveDelete(schoolRef);
  if (originalFlag?.exists) {
    await flagRef.set(originalFlag.data);
  } else if (originalFlag) {
    await flagRef.delete();
  }
}

(async () => {
  const flagSnap = await flagRef.get();
  originalFlag = {exists: flagSnap.exists, data: flagSnap.data()};
  canaryEmail = `security-audio-canary-${suffix}@lumi.invalid`;
  canaryPassword = `${crypto.randomBytes(24).toString("base64url")}Aa1!`;
  const user = await auth.createUser({
    email: canaryEmail,
    password: canaryPassword,
    emailVerified: true,
    displayName: "Lumi security audio canary",
  });
  uid = user.uid;

  await schoolRef.set({name: "Lumi security audio canary", isActive: false});
  await db.doc(`schools/${schoolId}/classes/${classId}`).set({
    schoolId,
    name: "Security canary",
    studentIds: [studentId],
  });
  await db.doc(`schools/${schoolId}/students/${studentId}`).set({
    schoolId,
    classId,
    parentIds: [uid],
    firstName: "Synthetic",
    pendingDeletion: false,
  });
  await logRef.set({
    schoolId,
    logId,
    classId,
    studentId,
    parentId: uid,
    loggedByRole: "parent",
    minutesRead: 1,
    status: "completed",
    bookTitles: ["Synthetic security canary"],
    createdAt: admin.firestore.Timestamp.now(),
    comprehensionAudioUploaded: false,
  });
  await flagRef.set({
    ...(originalFlag.data || {}),
    enabled: true,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const sourceBytes = fs.readFileSync(
    path.join(__dirname, "..", "test", "fixtures", "valid-tone.m4a")
  );
  await bucket.file(pendingPath).save(sourceBytes, {
    resumable: false,
    validation: "crc32c",
    metadata: {
      contentType: "audio/mp4",
      metadata: {ownerUid: uid, schoolId, logId, studentId},
    },
  });

  const idToken = await signInCanaryUser();
  const result = await callConfirm(idToken);
  assert(result?.confirmed === true, "Callable did not confirm the upload");
  assert(
    result.validationVersion === "ffmpeg-aac-mono-v1",
    "Unexpected validation version"
  );

  const [receiptSnap, pendingExists, canonicalExists, canonicalBytes] =
    await Promise.all([
      logRef.get(),
      bucket.file(pendingPath).exists(),
      bucket.file(canonicalPath).exists(),
      bucket.file(canonicalPath).download(),
    ]);
  const receipt = receiptSnap.data();
  const sha256 = crypto.createHash("sha256").update(canonicalBytes[0]).digest("hex");
  assert(pendingExists[0] === false, "Pending object was not removed");
  assert(canonicalExists[0] === true, "Canonical object was not created");
  assert(receipt.comprehensionAudioUploaded === true, "Receipt was not stamped");
  assert(receipt.comprehensionAudioPath === canonicalPath, "Receipt path mismatch");
  assert(receipt.comprehensionAudioValidationVersion === result.validationVersion,
    "Receipt validation version mismatch");
  assert(receipt.comprehensionAudioSha256 === sha256, "Canonical hash mismatch");
  assert(/^\d+$/.test(receipt.comprehensionAudioObjectGeneration),
    "Canonical generation is missing");
  assert(/^\d+$/.test(receipt.comprehensionAudioSourceGeneration),
    "Source generation is missing");
  assert(receipt.comprehensionAudioValidatedDurationMs >= 500,
    "Validated duration is missing");

  console.log(JSON.stringify({
    ok: true,
    projectId,
    validationVersion: result.validationVersion,
    durationSec: result.durationSec,
    canonicalBytes: canonicalBytes[0].length,
    pendingRemoved: true,
    canonicalReceiptVerified: true,
  }));
})().catch((error) => {
  console.error("Canary failed:", error.message);
  process.exitCode = 1;
}).finally(async () => {
  try {
    await cleanup();
    console.log("Canary cleanup complete; recording flag restored.");
  } catch (error) {
    console.error("Canary cleanup failed:", error.message);
    process.exitCode = 1;
  }
  await admin.app().delete();
});
