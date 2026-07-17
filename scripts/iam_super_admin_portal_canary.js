#!/usr/bin/env node
"use strict";

// Authenticated production canary for the super-admin portal's dedicated
// runtime identity. Uses one disposable super-admin and school and removes all
// synthetic data, objects and audit rows in finally. No credentials or signed
// URLs are printed or persisted.

const fs = require("node:fs");
const crypto = require("node:crypto");
const admin = require("../functions/node_modules/firebase-admin");

const PROJECT_ID = "lumi-ninc-au";
const BUCKET = "lumi-ninc-au.firebasestorage.app";
const ORIGIN = "https://lumi-dev-admin-au.web.app";

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
    throw new Error("Synthetic super-admin sign-in failed");
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
  const schoolId = `iam_super_portal_${nonce}`;
  const email = `iam-super-admin-${nonce}@example.invalid`;
  const password = `${crypto.randomBytes(24).toString("base64url")}Aa1!`;
  const logoPath = `schools/${schoolId}/logo.png`;
  let uid = null;

  try {
    const user = await auth.createUser({email, password, displayName: "IAM canary"});
    uid = user.uid;
    await Promise.all([
      db.doc(`superAdmins/${uid}`).set({email, createdFor: "iam-canary"}),
      db.doc(`schools/${schoolId}`).set({name: "IAM super-admin portal canary"}),
    ]);
    const idToken = await signIn(email, password);
    const session = await fetch(`${ORIGIN}/api/auth`, {
      method: "POST",
      headers: {"content-type": "application/json", origin: ORIGIN},
      body: JSON.stringify({idToken}),
      redirect: "manual",
    });
    const sessionBody = await session.json();
    const cookie = (session.headers.get("set-cookie") ?? "").split(";")[0];
    if (!session.ok || sessionBody.status !== "success" || !cookie.startsWith("__session=")) {
      throw new Error(`Super-admin session failed: HTTP_${session.status}`);
    }
    const sessionSegments = cookie.slice("__session=".length).split(".").length;
    if (sessionSegments !== 2) {
      throw new Error(`Unexpected session-cookie structure: ${sessionSegments} segments`);
    }
    const headers = {cookie, origin: ORIGIN};

    const dashboard = await fetch(`${ORIGIN}/api/dashboard`, {headers});
    if (!dashboard.ok) throw new Error("Super-admin Firestore dashboard read failed");

    const png = Buffer.from(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2nYQAAAAASUVORK5CYII=",
      "base64",
    );
    const form = new FormData();
    form.append("file", new File([png], "canary.png", {type: "image/png"}));
    const upload = await fetch(`${ORIGIN}/api/schools/${schoolId}/logo`, {
      method: "POST",
      headers,
      body: form,
    });
    const uploadBody = await upload.json();
    if (!upload.ok || typeof uploadBody.logoUrl !== "string") {
      throw new Error("Super-admin signed logo upload failed");
    }
    const media = await fetch(uploadBody.logoUrl, {headers: {range: "bytes=0-7"}});
    const mediaHeader = Buffer.from(await media.arrayBuffer());
    if (![200, 206].includes(media.status) || !mediaHeader.subarray(1, 4).equals(Buffer.from("PNG"))) {
      throw new Error("Super-admin signed logo URL was not readable");
    }

    const reconcile = await fetch(`${ORIGIN}/api/storage-usage/reconcile`, {
      method: "POST",
      headers,
    });
    if (!reconcile.ok) throw new Error("Super-admin Storage reconciliation failed");

    console.log("PASS super-admin Auth session-cookie permission");
    console.log("PASS super-admin Firestore read/write");
    console.log("PASS super-admin bucket access + self-scoped signing");
  } finally {
    await bucket.file(logoPath).delete({ignoreNotFound: true}).catch(() => undefined);
    await db.recursiveDelete(db.doc(`schools/${schoolId}`)).catch(() => undefined);
    if (uid) await db.doc(`superAdmins/${uid}`).delete().catch(() => undefined);
    await db.collection("adminAuditLog").where("targetId", "==", schoolId).get()
      .then(async (snapshot) => {
        await Promise.all(snapshot.docs.map((doc) => doc.ref.delete()));
      })
      .catch(() => undefined);
    if (uid) await auth.deleteUser(uid).catch(() => undefined);
    await admin.app().delete();
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
