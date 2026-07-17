#!/usr/bin/env node
"use strict";

// One-time migration for the server-owned UID membership index used by the
// login fallback. Dry-run is the default. Pass --apply to write production.
// The script prints aggregate counts only; it never prints UIDs or user data.

const admin = require("../functions/node_modules/firebase-admin");

const PROJECT_ID = "lumi-ninc-au";
const APPLY = process.argv.includes("--apply");

function membershipFromDoc(doc, userType) {
  const schoolRef = doc.ref.parent.parent;
  if (!schoolRef || schoolRef.parent.id !== "schools") return null;
  return {
    uid: doc.id,
    schoolId: schoolRef.id,
    userType,
  };
}

async function main() {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
  });
  const db = admin.firestore();
  const [staffSnapshot, parentSnapshot] = await Promise.all([
    db.collectionGroup("users").get(),
    db.collectionGroup("parents").get(),
  ]);

  const memberships = new Map();
  let ignored = 0;
  let conflicts = 0;
  for (const [snapshot, userType] of [
    [staffSnapshot, "user"],
    [parentSnapshot, "parent"],
  ]) {
    for (const doc of snapshot.docs) {
      const membership = membershipFromDoc(doc, userType);
      if (!membership) {
        ignored += 1;
        continue;
      }
      const previous = memberships.get(membership.uid);
      if (
        previous &&
        (previous.schoolId !== membership.schoolId ||
          previous.userType !== membership.userType)
      ) {
        conflicts += 1;
        continue;
      }
      memberships.set(membership.uid, membership);
    }
  }

  if (conflicts > 0) {
    throw new Error(
      `Refusing migration: ${conflicts} UID membership conflict(s) require review.`,
    );
  }

  let existing = 0;
  let changed = 0;
  const writes = [];
  for (const membership of memberships.values()) {
    const ref = db.doc(`userMembershipIndex/${membership.uid}`);
    const current = await ref.get();
    if (
      current.exists &&
      current.data()?.schoolId === membership.schoolId &&
      current.data()?.userType === membership.userType &&
      current.data()?.userId === membership.uid
    ) {
      existing += 1;
      continue;
    }
    changed += 1;
    writes.push({ref, membership});
  }

  console.log(JSON.stringify({
    mode: APPLY ? "apply" : "dry-run",
    staffMemberships: staffSnapshot.size,
    parentMemberships: parentSnapshot.size,
    uniqueMemberships: memberships.size,
    ignored,
    conflicts,
    alreadyCurrent: existing,
    writesRequired: changed,
  }, null, 2));

  if (!APPLY || writes.length === 0) return;

  for (let offset = 0; offset < writes.length; offset += 400) {
    const batch = db.batch();
    for (const {ref, membership} of writes.slice(offset, offset + 400)) {
      batch.set(ref, {
        userId: membership.uid,
        schoolId: membership.schoolId,
        userType: membership.userType,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
  console.log(`Applied ${writes.length} membership index write(s).`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : "Migration failed");
  process.exitCode = 1;
});
