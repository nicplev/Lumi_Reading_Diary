import test, { after, before, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { deleteApp, getApps, initializeApp, type App } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import type { Storage } from "firebase-admin/storage";
import {
  comprehensionAudioObjectPath,
  comprehensionAudioUploadObjectPath,
  runComprehensionRetentionNow,
} from "../src/comprehensionAudioActions";
import {
  getComprehensionRetentionConfig,
  setComprehensionRetentionConfig,
} from "../src/setComprehensionRetentionConfig";

const PROJECT_ID = "demo-lumi-server-ops-audio";
let app: App;
const deletedPaths: string[] = [];

const storage = {
  bucket: () => ({
    file: (path: string) => ({
      delete: async () => {
        deletedPaths.push(path);
      },
    }),
  }),
} as unknown as Storage;

before(() => {
  app = initializeApp({ projectId: PROJECT_ID }, "server-ops-audio-test");
});

after(async () => {
  if (getApps().includes(app)) await deleteApp(app);
});

beforeEach(async () => {
  const db = getFirestore(app);
  for (const collection of ["adminAuditLog", "platformConfig", "schools"]) {
    await db.recursiveDelete(db.collection(collection));
  }
  deletedPaths.length = 0;
});

test("platform fallback rejects seven days and accepts thirty", async () => {
  const db = getFirestore(app);
  const actor = { uid: "super-admin-1", email: "admin@example.test" };
  await assert.rejects(
    setComprehensionRetentionConfig(db, actor, { retentionDays: 7 })
  );

  await setComprehensionRetentionConfig(db, actor, { retentionDays: 30 });
  const config = await getComprehensionRetentionConfig(db);
  assert.equal(config.enabled, true);
  assert.equal(config.retentionDays, 30);
});

test("manual retention matches cron precedence and canonical path safety", async () => {
  const db = getFirestore(app);
  const old = Timestamp.fromMillis(Date.now() - 30 * 86_400_000);
  await db.doc("platformConfig/comprehensionRetention").set({
    enabled: false,
    retentionDays: 30,
  });
  await db.doc("schools/legacy").set({
    settings: { comprehensionRecording: { retentionDays: 7 } },
  });
  await db.doc("schools/long").set({
    settings: { comprehensionRecording: { retentionDays: 90 } },
  });

  const good = db.doc("schools/legacy/readingLogs/good");
  const injected = db.doc("schools/legacy/readingLogs/injected");
  const retained = db.doc("schools/long/readingLogs/retained");
  await good.set({
    createdAt: old,
    comprehensionAudioUploaded: true,
    comprehensionAudioPath: comprehensionAudioObjectPath("legacy", "good"),
  });
  await injected.set({
    createdAt: old,
    comprehensionAudioUploaded: true,
    comprehensionAudioPath: "schools/other/comprehension_audio/private.m4a",
  });
  await retained.set({
    createdAt: old,
    comprehensionAudioUploaded: true,
    comprehensionAudioPath: comprehensionAudioObjectPath("long", "retained"),
  });

  const stats = await runComprehensionRetentionNow(db, storage, {
    uid: "super-admin-1",
    email: "admin@example.test",
  });

  assert.deepEqual(stats.retentionPolicyCounts, { 7: 1, 90: 1 });
  assert.equal(stats.deletedCount, 1);
  assert.equal(stats.failedCount, 1);
  assert.equal(stats.legacySevenDaySchoolCount, 1);
  assert.equal(stats.trigger, "manual");
  assert.deepEqual(deletedPaths.sort(), [
    comprehensionAudioObjectPath("legacy", "good"),
    comprehensionAudioUploadObjectPath("legacy", "good"),
    comprehensionAudioObjectPath("legacy", "injected"),
    comprehensionAudioUploadObjectPath("legacy", "injected"),
  ].sort());
  assert.equal(
    deletedPaths.includes("schools/other/comprehension_audio/private.m4a"),
    false
  );

  assert.equal((await good.get()).data()?.comprehensionAudioUploaded, false);
  assert.equal((await injected.get()).data()?.comprehensionAudioUploaded, false);
  assert.ok((await injected.get()).data()?.comprehensionAudioPathRejectedAt);
  assert.equal((await retained.get()).data()?.comprehensionAudioUploaded, true);

  const storedStats = (await db.doc(
    "platformConfig/comprehensionRetention"
  ).get()).data()?.lastRunStats;
  assert.equal(storedStats.trigger, "manual");
  assert.equal(storedStats.legacySevenDaySchoolCount, 1);
});
