// Live Storage-usage tracking for the default bucket.
//
// The super-admin dashboard shows how many bytes of comprehension audio
// (and other binary content) the platform is holding, so growth/cost
// problems surface before the bill does. Nothing in GCS exposes "bytes
// under a prefix" cheaply, so we maintain our own counters:
//
//  - onObjectFinalized / onObjectDeleted increment a single counter doc
//    (opsMetrics/storageUsage) the moment an object lands or is removed.
//    Storage events are at-least-once and unretried (`retry: false`), and
//    an unversioned-bucket overwrite emits a delete for the old generation
//    plus a finalize for the new one — so the live counters can drift by
//    a bounded amount.
//  - reconcileStorageUsage lists the whole bucket nightly and REPLACES the
//    counters, healing any drift and appending a daily history entry for
//    the dashboard's trend sparkline.
//
// Same incremental-delta + scheduled-reconcile philosophy as
// stats_aggregation.ts. Admin-SDK deletes (retention cron, portal bulk
// delete) still emit OBJECT_DELETE — no changes needed in those paths.
//
// opsMetrics/* is deliberately NOT under platformConfig: platformConfig
// docs are `get`-able by any signed-in client (firestore.rules), and this
// doc carries per-school byte maps. opsMetrics has an explicit deny-all
// rules block; only Admin SDK readers/writers touch it.

import * as functions from "firebase-functions/v1";
import {
  onObjectFinalized,
  onObjectDeleted,
  StorageEvent,
} from "firebase-functions/v2/storage";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import {localDateString} from "./dateUtils";
import {recordCronRun} from "./ops_heartbeat";

const USAGE_DOC = "opsMetrics/storageUsage";
const BUCKET = "lumi-ninc-au.firebasestorage.app";
const SYDNEY_TZ = "Australia/Sydney";
const HISTORY_CAP = 90;

export type StorageCategory =
  | "comprehensionAudio"
  | "communityBookCovers"
  | "bookCovers"
  | "schoolLogos"
  | "other";

export interface ObjectClassification {
  category: StorageCategory;
  schoolId?: string;
}

const AUDIO_RE = /^schools\/([^/]+)\/comprehension_audio\//;
const LOGO_RE = /^schools\/([^/]+)\/logo\.[^/]+$/;

/**
 * Maps a Storage object name to a usage category (+ owning school for
 * audio). Classifies EVERYTHING — storage triggers cannot prefix-filter,
 * and the nightly reconcile scans the whole bucket, so both paths must
 * agree on how every object is bucketed. Unknown prefixes land in
 * "other" rather than being dropped, so the total always matches the
 * real bucket size.
 * @param {string} name The full object name (path within the bucket).
 * @return {ObjectClassification} Category + schoolId where applicable.
 */
export function classifyObject(name: string): ObjectClassification {
  const audio = AUDIO_RE.exec(name);
  if (audio) return {category: "comprehensionAudio", schoolId: audio[1]};
  if (name.startsWith("community_books/covers/")) {
    return {category: "communityBookCovers"};
  }
  if (name.startsWith("bookCovers/")) return {category: "bookCovers"};
  if (LOGO_RE.test(name)) return {category: "schoolLogos"};
  return {category: "other"};
}

/**
 * Builds the nested increment payload for one finalize/delete event.
 * Nested maps + `set(..., {merge: true})` (deep merge) rather than
 * dotted-path `update()` so the very first event creates the doc.
 * @param {string} name Object name.
 * @param {number} size Object size in bytes.
 * @param {1 | -1} sign +1 for finalize, -1 for delete.
 * @return {Record<string, unknown>} Payload for set-merge.
 */
function usageDelta(
  name: string,
  size: number,
  sign: 1 | -1,
): Record<string, unknown> {
  const {category, schoolId} = classifyObject(name);
  const inc = admin.firestore.FieldValue.increment;
  const delta: Record<string, unknown> = {
    totalBytes: inc(sign * size),
    totalObjects: inc(sign),
    categories: {[category]: {bytes: inc(sign * size), objects: inc(sign)}},
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (category === "comprehensionAudio" && schoolId) {
    delta.audioPerSchool = {
      [schoolId]: {bytes: inc(sign * size), objects: inc(sign)},
    };
  }
  return delta;
}

/**
 * Applies one storage event to the counter doc. Worst-case write rate is
 * a retention bulk run, which deletes sequentially (awaited per doc), so
 * the single-doc counter stays well under Firestore's sustained-write
 * guidance; a shard-per-category split is the future option if that ever
 * changes. Any missed/duplicated event is healed by the nightly
 * reconcile, so failures here only log.
 * @param {StorageEvent} event The finalize/delete CloudEvent.
 * @param {1 | -1} sign +1 for finalize, -1 for delete.
 * @return {Promise<void>} Resolves when the counter write completes.
 */
async function applyStorageEvent(
  event: StorageEvent,
  sign: 1 | -1,
): Promise<void> {
  const name = event.data.name;
  if (!name) return;
  const size = Number(event.data.size) || 0;
  try {
    await admin
      .firestore()
      .doc(USAGE_DOC)
      .set(usageDelta(name, size, sign), {merge: true});
  } catch (err) {
    functions.logger.error("storageUsage.eventApplyFailed", {
      name,
      sign,
      error: err instanceof Error ? err.message : String(err),
    });
  }
}

export const trackStorageObjectFinalized = onObjectFinalized(
  {bucket: BUCKET, region: "australia-southeast1", memory: "256MiB"},
  (event) => applyStorageEvent(event, 1),
);

export const trackStorageObjectDeleted = onObjectDeleted(
  {bucket: BUCKET, region: "australia-southeast1", memory: "256MiB"},
  (event) => applyStorageEvent(event, -1),
);

interface CategoryUsage {
  bytes: number;
  objects: number;
}

export interface StorageReconcileStats {
  scannedObjects: number;
  totalBytes: number;
  driftBytes: number;
  driftObjects: number;
  durationMs: number;
}

/**
 * Full-bucket scan: sums bytes/objects per category (and per school for
 * audio), records drift vs the live counters, upserts today's history
 * entry, then REPLACES the counter doc wholesale. Objects uploaded or
 * deleted mid-scan produce bounded one-night drift — the next reconcile
 * heals it, same trade-off the stats reconciler makes.
 * @param {string} performedBy Actor label for the structured log line.
 * @return {Promise<StorageReconcileStats>} Scan summary.
 */
export async function performStorageReconcile(
  performedBy: string,
): Promise<StorageReconcileStats> {
  const startedAtMs = Date.now();
  const db = admin.firestore();
  const bucket = admin.storage().bucket(BUCKET);

  // Live values BEFORE the scan, for the drift measurement + history.
  const beforeSnap = await db.doc(USAGE_DOC).get();
  const before = beforeSnap.data() ?? {};
  const liveBytes = typeof before.totalBytes === "number" ?
    before.totalBytes : 0;
  const liveObjects = typeof before.totalObjects === "number" ?
    before.totalObjects : 0;
  const priorHistory: Array<{
    date: string;
    totalBytes: number;
    audioBytes: number;
    totalObjects: number;
  }> = Array.isArray(before.history) ? before.history : [];

  let totalBytes = 0;
  let totalObjects = 0;
  const categories: Partial<Record<StorageCategory, CategoryUsage>> = {};
  const audioPerSchool: Record<string, CategoryUsage> = {};

  let pageToken: string | undefined;
  do {
    const [files, nextQuery] = await bucket.getFiles({
      autoPaginate: false,
      maxResults: 1000,
      pageToken,
    });
    for (const file of files) {
      const size = Number(file.metadata.size) || 0;
      const {category, schoolId} = classifyObject(file.name);
      totalBytes += size;
      totalObjects += 1;
      const cat = categories[category] ?? {bytes: 0, objects: 0};
      cat.bytes += size;
      cat.objects += 1;
      categories[category] = cat;
      if (category === "comprehensionAudio" && schoolId) {
        const school = audioPerSchool[schoolId] ?? {bytes: 0, objects: 0};
        school.bytes += size;
        school.objects += 1;
        audioPerSchool[schoolId] = school;
      }
    }
    pageToken = (nextQuery as {pageToken?: string} | null)?.pageToken;
  } while (pageToken);

  const audioBytes = categories.comprehensionAudio?.bytes ?? 0;
  const today = localDateString(new Date(startedAtMs), SYDNEY_TZ);
  const history = [
    ...priorHistory.filter((h) => h && h.date !== today),
    {date: today, totalBytes, audioBytes, totalObjects},
  ]
    .sort((a, b) => a.date.localeCompare(b.date))
    .slice(-HISTORY_CAP);

  const stats: StorageReconcileStats = {
    scannedObjects: totalObjects,
    totalBytes,
    driftBytes: liveBytes - totalBytes,
    driftObjects: liveObjects - totalObjects,
    durationMs: Date.now() - startedAtMs,
  };

  // Full replace (no merge): stale audioPerSchool/category keys from
  // deleted schools or drifted increments must not survive the heal.
  await db.doc(USAGE_DOC).set({
    totalBytes,
    totalObjects,
    categories,
    audioPerSchool,
    lastReconcile: {
      at: admin.firestore.Timestamp.fromMillis(startedAtMs),
      durationMs: stats.durationMs,
      scannedObjects: stats.scannedObjects,
      driftBytes: stats.driftBytes,
      driftObjects: stats.driftObjects,
    },
    history,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  functions.logger.info("storageUsage.reconcile.completed", {
    performedBy,
    ...stats,
  });
  return stats;
}

export const reconcileStorageUsage = onSchedule(
  {
    schedule: "30 2 * * *",
    timeZone: SYDNEY_TZ,
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    try {
      await performStorageReconcile("system:reconcileStorageUsage");
      await recordCronRun("reconcileStorageUsage", "ok");
    } catch (err) {
      await recordCronRun("reconcileStorageUsage", "error",
        err instanceof Error ? err.message : String(err));
      throw err;
    }
  },
);
