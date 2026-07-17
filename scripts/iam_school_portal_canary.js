#!/usr/bin/env node
"use strict";

// Authenticated production canary for the school portal's dedicated runtime
// identity. Uses one disposable teacher and school, never prints session/reset
// credentials, and removes the uploaded object and all synthetic records.

const fs = require("node:fs");
const crypto = require("node:crypto");
const admin = require("../functions/node_modules/firebase-admin");

const PROJECT_ID = "lumi-ninc-au";
const BUCKET = "lumi-ninc-au.firebasestorage.app";
const ORIGIN = "https://lumi-school-admin-au.web.app";

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
    throw new Error("Synthetic teacher sign-in failed");
  }
  return body.idToken;
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
  const schoolId = `iam_school_portal_${nonce}`;
  const email = `iam-school-teacher-${nonce}@example.invalid`;
  const password = `${crypto.randomBytes(24).toString("base64url")}Aa1!`;
  let uid = null;
  let uploadedPath = null;

  try {
    const user = await auth.createUser({email, password, displayName: "IAM canary"});
    uid = user.uid;
    await Promise.all([
      db.doc(`schools/${schoolId}`).set({name: "IAM school portal canary"}),
      db.doc(`schools/${schoolId}/users/${uid}`).set({
        role: "teacher",
        email,
        fullName: "IAM canary",
        isActive: true,
      }),
    ]);
    const idToken = await signIn(email, password);
    const sessionResponse = await fetch(`${ORIGIN}/api/auth/session`, {
      method: "POST",
      headers: {"content-type": "application/json", origin: ORIGIN},
      body: JSON.stringify({idToken}),
      redirect: "manual",
    });
    const sessionBody = await sessionResponse.json();
    const setCookie = sessionResponse.headers.get("set-cookie") ?? "";
    const cookie = setCookie.split(";")[0];
    if (!sessionResponse.ok || sessionBody.schoolId !== schoolId || !cookie.startsWith("__session=")) {
      throw new Error(`School portal session failed: HTTP_${sessionResponse.status}`);
    }
    const headers = {cookie, origin: ORIGIN};

    const me = await fetch(`${ORIGIN}/api/auth/me`, {headers});
    const meBody = await me.json();
    if (!me.ok || meBody.uid !== uid || meBody.schoolId !== schoolId) {
      throw new Error("School portal authenticated read failed");
    }

    const reset = await fetch(`${ORIGIN}/api/profile/reset-password`, {
      method: "POST",
      headers,
    });
    const resetBody = await reset.json();
    if (!reset.ok || typeof resetBody.link !== "string") {
      throw new Error("School portal Auth reset-link operation failed");
    }

    const png = Buffer.from(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2nYQAAAAASUVORK5CYII=",
      "base64",
    );
    const form = new FormData();
    form.append("file", new File([png], "canary.png", {type: "image/png"}));
    const upload = await fetch(`${ORIGIN}/api/books/cover-upload`, {
      method: "POST",
      headers,
      body: form,
    });
    const uploadBody = await upload.json();
    if (!upload.ok || typeof uploadBody.url !== "string") {
      throw new Error("School portal Storage upload failed");
    }
    const encodedPath = new URL(uploadBody.url).pathname.split("/o/")[1];
    uploadedPath = encodedPath ? decodeURIComponent(encodedPath) : null;
    if (!uploadedPath?.startsWith(`bookCovers/${schoolId}/`)) {
      throw new Error("School portal uploaded an unexpected object path");
    }

    console.log("PASS school portal Firestore session/read");
    console.log("PASS school portal Auth get/update/sendEmail permissions");
    console.log("PASS school portal bucket-scoped upload");
  } finally {
    if (uploadedPath) {
      await bucket.file(uploadedPath).delete({ignoreNotFound: true})
        .catch(() => undefined);
    }
    await db.recursiveDelete(db.doc(`schools/${schoolId}`)).catch(() => undefined);
    if (uid) await auth.deleteUser(uid).catch(() => undefined);
    await admin.app().delete();
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
