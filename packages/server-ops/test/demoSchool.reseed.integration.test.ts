import test, { after, before } from "node:test";
import assert from "node:assert/strict";
import { getApps, initializeApp, deleteApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { buildDemoSchoolPlan } from "../src/demoSchool/plan";
import { reseedDemoSchool } from "../src/demoSchool/reseed";

const PROJECT = "demo-lumi-reseed";
const app = initializeApp({ projectId: PROJECT, storageBucket: `${PROJECT}.appspot.com` });
const db = getFirestore(app);
const auth = getAuth(app);
const storage = getStorage(app);

before(async () => {
  await db.doc("schools/lumi_demo_primary_school").set({ isDemo: true, name: "Old demo" });
  await db.doc("demoAccess/state").set({ sentinel: "password-state-survives" });
  const contributor = buildDemoSchoolPlan().authUsers[0].uid;
  await db.doc("community_books/9780000000001").set({
    isbn: "9780000000001",
    contributedBy: contributor,
  });
  await storage.bucket().file("community_books/covers/9780000000001.jpg").save(Buffer.from("cover"));
});
after(async () => {
  await Promise.all(getApps().map((entry) => deleteApp(entry)));
});

test("fenced reseed preserves password state and finalises exact demo claims", async () => {
  const result = await reseedDemoSchool(
    auth,
    db,
    storage,
    { uid: "test-super-admin", email: "security-test@lumi-reading.com" },
    { trigger: "manual", now: new Date("2026-07-17T09:00:00+10:00") }
  );
  assert.ok(result.docsWritten > 450);
  assert.equal((await db.doc("demoAccess/state").get()).data()?.sentinel, "password-state-survives");
  assert.equal((await db.doc("demoAccess/reseedStatus").get()).data()?.state, "succeeded");
  assert.equal((await db.doc("schools/lumi_demo_primary_school").get()).data()?.isDemo, true);
  assert.equal((await db.doc("schools/lumi_demo_primary_school/allocations/demo_alloc_3g_bytitle").get()).exists, true);
  assert.equal((await db.doc("schools/lumi_demo_primary_school/allocations/demo_alloc_3g_bylevel").get()).exists, false);
  assert.equal((await db.doc("community_books/9780000000001").get()).exists, false);
  assert.equal((await storage.bucket().file("community_books/covers/9780000000001.jpg").exists())[0], false);

  const plan = buildDemoSchoolPlan(new Date("2026-07-17T09:00:00+10:00"));
  const sharedAdmin = plan.authUsers.find((user) => user.key === "sharedadmin")!;
  const teacher = plan.authUsers.find((user) => user.key === "teacher")!;
  assert.deepEqual((await auth.getUser(sharedAdmin.uid)).customClaims, {
    demoAccount: true,
    demoSchoolId: "lumi_demo_primary_school",
    schoolId: "lumi_demo_primary_school",
    demoAdminMfaExempt: true,
    demoReadOnly: true,
  });
  assert.deepEqual((await auth.getUser(teacher.uid)).customClaims, {
    demoAccount: true,
    demoSchoolId: "lumi_demo_primary_school",
    schoolId: "lumi_demo_primary_school",
  });
});

test("fresh running lease refuses overlap", async () => {
  await db.doc("demoAccess/reseedStatus").set({
    state: "running",
    leaseId: "other-worker",
    startedAt: new Date(),
    heartbeatAt: new Date(),
  });
  await assert.rejects(
    reseedDemoSchool(
      auth,
      db,
      storage,
      { uid: "second-admin" },
      { trigger: "manual" }
    ),
    /already running/
  );
});
