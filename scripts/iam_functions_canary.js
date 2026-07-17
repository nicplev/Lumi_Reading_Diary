#!/usr/bin/env node
"use strict";

// Production IAM capability canary. It creates one random Auth user and one
// isolated parent document, calls only the two named Functions, and deletes all
// synthetic state in finally. Passwords, tokens and the public Firebase API key
// are never printed or written to disk.

const fs = require("node:fs");
const crypto = require("node:crypto");
const admin = require("../functions/node_modules/firebase-admin");

const PROJECT_ID = "lumi-ninc-au";
const REGION = "australia-southeast1";
const FUNCTIONS_ORIGIN =
  `https://${REGION}-${PROJECT_ID}.cloudfunctions.net`;

function firebaseApiKey() {
  const options = fs.readFileSync("lib/firebase_options.dart", "utf8");
  const webBlock = options.match(
    /static const FirebaseOptions web = FirebaseOptions\(([\s\S]*?)\n\s*\);/,
  );
  const key = webBlock?.[1]?.match(/apiKey:\s*'([^']+)'/)?.[1];
  if (typeof key !== "string" || key.length === 0) {
    throw new Error("Firebase web API key is unavailable");
  }
  return key;
}

async function callFunction(name, idToken, data) {
  const response = await fetch(`${FUNCTIONS_ORIGIN}/${name}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify({data}),
  });
  const body = await response.json();
  if (!response.ok || body.error) {
    const status = body.error?.status ?? `HTTP_${response.status}`;
    throw new Error(`${name} failed: ${status}`);
  }
  return body.result;
}

async function waitForDocumentState(ref, expectedExists) {
  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    if ((await ref.get()).exists === expectedExists) return;
    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
  throw new Error(
    `Timed out waiting for membership index ${expectedExists ? "create" : "delete"}`,
  );
}

async function main() {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
  });
  const auth = admin.auth();
  const db = admin.firestore();
  const nonce = crypto.randomBytes(12).toString("hex");
  const schoolId = `iam_canary_${nonce}`;
  const email = `iam-canary-${nonce}@example.invalid`;
  const password = `${crypto.randomBytes(24).toString("base64url")}Aa1!`;
  let uid = null;

  try {
    const user = await auth.createUser({email, password});
    uid = user.uid;
    const parentRef = db.doc(`schools/${schoolId}/parents/${uid}`);
    const membershipIndexRef = db.doc(`userMembershipIndex/${uid}`);
    await parentRef.set({
      role: "parent",
      linkedChildren: [],
      fcmToken: `not-a-real-fcm-token-${nonce}`,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const signIn = await fetch(
      `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${firebaseApiKey()}`,
      {
        method: "POST",
        headers: {
          "content-type": "application/json",
          // Matches the Browser key's explicit localhost restriction.
          referer: "http://localhost/",
        },
        body: JSON.stringify({email, password, returnSecureToken: true}),
      },
    );
    const signInBody = await signIn.json();
    if (!signIn.ok || typeof signInBody.idToken !== "string") {
      throw new Error("Synthetic user sign-in failed");
    }

    await waitForDocumentState(membershipIndexRef, true);
    const resolution = await callFunction(
      "resolveUserSchoolByUid",
      signInBody.idToken,
      {},
    );
    if (
      resolution.schoolId !== schoolId ||
      resolution.userType !== "parent" ||
      resolution.userId !== uid
    ) {
      throw new Error("UID membership resolver returned an unexpected result");
    }

    const mfa = await callFunction(
      "syncUserMfaProfileState",
      signInBody.idToken,
      {role: "parent", schoolId, enabled: false},
    );
    if (mfa.updated !== true) {
      throw new Error("Auth/Firestore canary returned an unexpected result");
    }

    const fcm = await callFunction(
      "sendTestReadingReminder",
      signInBody.idToken,
      {schoolId},
    );
    if (fcm.sent !== false || fcm.reason !== "send-failed") {
      throw new Error("FCM canary did not reach the expected invalid-token path");
    }
    await parentRef.delete();
    await waitForDocumentState(membershipIndexRef, false);
    console.log("PASS UID membership index create/resolve/delete lifecycle");
    console.log("PASS Auth lookup + Firestore update");
    console.log("PASS FCM send permission (expected invalid-token response)");
  } finally {
    if (uid) {
      await db.doc(`schools/${schoolId}/parents/${uid}`).delete()
        .catch(() => undefined);
      await db.doc(`schools/${schoolId}`).delete().catch(() => undefined);
      await auth.deleteUser(uid).catch(() => undefined);
    }
    await admin.app().delete();
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
