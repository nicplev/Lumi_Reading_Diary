#!/usr/bin/env node
"use strict";

// Production least-privilege audio capability canary. All identities, school
// data and objects use a random namespace and are removed in finally. No child
// data, passwords, ID tokens or signed URLs are printed or persisted.

const fs = require("node:fs");
const crypto = require("node:crypto");
const admin = require("../functions/node_modules/firebase-admin");

const PROJECT_ID = "lumi-ninc-au";
const REGION = "australia-southeast1";
const BUCKET = "lumi-ninc-au.firebasestorage.app";
const ORIGIN = `https://${REGION}-${PROJECT_ID}.cloudfunctions.net`;

function firebaseApiKey() {
  const options = fs.readFileSync("lib/firebase_options.dart", "utf8");
  const webBlock = options.match(
    /static const FirebaseOptions web = FirebaseOptions\(([\s\S]*?)\n\s*\);/,
  );
  const key = webBlock?.[1]?.match(/apiKey:\s*'([^']+)'/)?.[1];
  if (!key) throw new Error("Firebase web API key is unavailable");
  return key;
}

async function signIn(email, password) {
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${firebaseApiKey()}`,
    {
      method: "POST",
      headers: {"content-type": "application/json", referer: "http://localhost/"},
      body: JSON.stringify({email, password, returnSecureToken: true}),
    },
  );
  const body = await response.json();
  if (!response.ok || typeof body.idToken !== "string") {
    throw new Error("Synthetic user sign-in failed");
  }
  return body.idToken;
}

async function callFunction(name, idToken, data) {
  const response = await fetch(`${ORIGIN}/${name}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify({data}),
  });
  const body = await response.json();
  if (!response.ok || body.error) {
    throw new Error(`${name} failed: ${body.error?.status ?? response.status}`);
  }
  return body.result;
}

async function main() {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
    storageBucket: BUCKET,
  });
  const auth = admin.auth();
  const db = admin.firestore();
  const bucket = admin.storage().bucket();
  const nonce = crypto.randomBytes(12).toString("hex");
  const schoolId = `iam_audio_canary_${nonce}`;
  const classId = `class_${nonce}`;
  const studentId = `student_${nonce}`;
  const logId = `log_${nonce}`;
  const pendingPath = `comprehension_audio_uploads/${schoolId}/${logId}.m4a`;
  const canonicalPath = `schools/${schoolId}/comprehension_audio/${logId}.m4a`;
  const password = `${crypto.randomBytes(24).toString("base64url")}Aa1!`;
  const users = [];

  try {
    for (const role of ["parent", "teacher"]) {
      users.push(await auth.createUser({
        email: `iam-audio-${role}-${nonce}@example.invalid`,
        password,
      }));
    }
    const [parent, teacher] = users;
    await Promise.all([
      db.doc(`schools/${schoolId}`).set({name: "IAM audio canary"}),
      db.doc(`schools/${schoolId}/parents/${parent.uid}`).set({
        role: "parent",
        linkedChildren: [studentId],
      }),
      db.doc(`schools/${schoolId}/users/${teacher.uid}`).set({role: "teacher"}),
      db.doc(`schools/${schoolId}/classes/${classId}`).set({
        teacherId: teacher.uid,
        teacherIds: [teacher.uid],
      }),
      db.doc(`schools/${schoolId}/readingLogs/${logId}`).set({
        parentId: parent.uid,
        loggedByRole: "parent",
        studentId,
        classId,
      }),
    ]);
    const tone = fs.readFileSync("functions/test/fixtures/valid-tone.m4a");
    await bucket.file(pendingPath).save(tone, {
      resumable: false,
      metadata: {
        contentType: "audio/mp4",
        metadata: {
          ownerUid: parent.uid,
          schoolId,
          logId,
          studentId,
        },
      },
    });

    const [parentToken, teacherToken] = await Promise.all([
      signIn(parent.email, password),
      signIn(teacher.email, password),
    ]);
    const confirmed = await callFunction(
      "confirmComprehensionAudioUpload",
      parentToken,
      {schoolId, logId, durationSec: 1},
    );
    if (confirmed.confirmed !== true || confirmed.validationVersion !== "ffmpeg-aac-mono-v1") {
      throw new Error("Audio confirmation returned an unexpected receipt");
    }

    const playback = await callFunction(
      "getComprehensionAudioUrl",
      teacherToken,
      {schoolId, logId},
    );
    if (typeof playback.url !== "string" || playback.expiresInSec !== 900) {
      throw new Error("Signed playback response was invalid");
    }
    const range = await fetch(playback.url, {headers: {range: "bytes=0-31"}});
    const header = Buffer.from(await range.arrayBuffer());
    if (![200, 206].includes(range.status) || !header.subarray(4, 8).equals(Buffer.from("ftyp"))) {
      throw new Error("Signed playback URL did not return validated media");
    }

    const deleted = await callFunction(
      "deleteComprehensionAudio",
      teacherToken,
      {schoolId, logId},
    );
    if (deleted.deleted !== true) {
      throw new Error("Audio deletion did not report success");
    }
    const [canonicalExists] = await bucket.file(canonicalPath).exists();
    const log = await db.doc(`schools/${schoolId}/readingLogs/${logId}`).get();
    if (canonicalExists || log.data()?.comprehensionAudioUploaded !== false) {
      throw new Error("Audio deletion postcondition failed");
    }

    console.log("PASS Storage read/write/delete + isolated validator invocation");
    console.log("PASS self-scoped signing + validated range playback");
    console.log("PASS audited teacher deletion");
  } finally {
    await bucket.file(pendingPath).delete({ignoreNotFound: true}).catch(() => undefined);
    await bucket.file(canonicalPath).delete({ignoreNotFound: true}).catch(() => undefined);
    await db.recursiveDelete(db.doc(`schools/${schoolId}`)).catch(() => undefined);
    await db.collection("adminAuditLog").where("targetId", "==", logId).get()
      .then(async (snapshot) => {
        await Promise.all(snapshot.docs.map((doc) => doc.ref.delete()));
      })
      .catch(() => undefined);
    for (const user of users) {
      const rateId = crypto.createHash("sha256").update(user.uid).digest("hex");
      await db.doc(`backendRateLimits/audioValidation_${rateId}`).delete()
        .catch(() => undefined);
      await auth.deleteUser(user.uid).catch(() => undefined);
    }
    await admin.app().delete();
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
