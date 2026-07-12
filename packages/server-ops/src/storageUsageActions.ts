import type { Firestore } from "firebase-admin/firestore";
import type { Storage } from "firebase-admin/storage";
import { logAuditEvent, type Actor } from "./audit";

// Portal "Reconcile now" for opsMetrics/storageUsage.
//
// DUPLICATES the scan in functions/src/storage_usage.ts
// (performStorageReconcile) — functions/ has no @lumi/* workspace deps,
// so sharing isn't possible without a packaging change; this follows the
// same established duplication as runComprehensionRetentionNow vs the
// cron's performCleanup. If you change the classifier or the doc shape,
// CHANGE BOTH FILES.

const USAGE_DOC = "opsMetrics/storageUsage";
const SYDNEY_TZ = "Australia/Sydney";
const HISTORY_CAP = 90;

type StorageCategory =
  | "comprehensionAudio"
  | "communityBookCovers"
  | "bookCovers"
  | "schoolLogos"
  | "other";

interface CategoryUsage {
  bytes: number;
  objects: number;
}

export interface StorageUsageReconcileStats {
  scannedObjects: number;
  totalBytes: number;
  driftBytes: number;
  driftObjects: number;
  durationMs: number;
}

const AUDIO_RE = /^schools\/([^/]+)\/comprehension_audio\//;
const LOGO_RE = /^schools\/([^/]+)\/logo\.[^/]+$/;

function classifyObject(name: string): {
  category: StorageCategory;
  schoolId?: string;
} {
  const audio = AUDIO_RE.exec(name);
  if (audio) return { category: "comprehensionAudio", schoolId: audio[1] };
  if (name.startsWith("community_books/covers/")) {
    return { category: "communityBookCovers" };
  }
  if (name.startsWith("bookCovers/")) return { category: "bookCovers" };
  if (LOGO_RE.test(name)) return { category: "schoolLogos" };
  return { category: "other" };
}

const sydneyDate = new Intl.DateTimeFormat("en-CA", {
  timeZone: SYDNEY_TZ,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});

export async function runStorageUsageReconcileNow(
  db: Firestore,
  storage: Storage,
  actor: Actor,
  options?: { bucketName?: string }
): Promise<StorageUsageReconcileStats> {
  const startedAtMs = Date.now();
  // The portal app now sets a default bucket at init; callers may still
  // pass NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET explicitly (defensive).
  const bucket = options?.bucketName
    ? storage.bucket(options.bucketName)
    : storage.bucket();

  const usageRef = db.doc(USAGE_DOC);
  const beforeSnap = await usageRef.get();
  const before = beforeSnap.data() ?? {};
  const liveBytes =
    typeof before.totalBytes === "number" ? before.totalBytes : 0;
  const liveObjects =
    typeof before.totalObjects === "number" ? before.totalObjects : 0;
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
      const { category, schoolId } = classifyObject(file.name);
      totalBytes += size;
      totalObjects += 1;
      const cat = categories[category] ?? { bytes: 0, objects: 0 };
      cat.bytes += size;
      cat.objects += 1;
      categories[category] = cat;
      if (category === "comprehensionAudio" && schoolId) {
        const school = audioPerSchool[schoolId] ?? { bytes: 0, objects: 0 };
        school.bytes += size;
        school.objects += 1;
        audioPerSchool[schoolId] = school;
      }
    }
    pageToken = (nextQuery as { pageToken?: string } | null)?.pageToken;
  } while (pageToken);

  const audioBytes = categories.comprehensionAudio?.bytes ?? 0;
  const today = sydneyDate.format(new Date(startedAtMs));
  const history = [
    ...priorHistory.filter((h) => h && h.date !== today),
    { date: today, totalBytes, audioBytes, totalObjects },
  ]
    .sort((a, b) => a.date.localeCompare(b.date))
    .slice(-HISTORY_CAP);

  const stats: StorageUsageReconcileStats = {
    scannedObjects: totalObjects,
    totalBytes,
    driftBytes: liveBytes - totalBytes,
    driftObjects: liveObjects - totalObjects,
    durationMs: Date.now() - startedAtMs,
  };

  await usageRef.set({
    totalBytes,
    totalObjects,
    categories,
    audioPerSchool,
    lastReconcile: {
      at: new Date(startedAtMs),
      durationMs: stats.durationMs,
      scannedObjects: stats.scannedObjects,
      driftBytes: stats.driftBytes,
      driftObjects: stats.driftObjects,
    },
    history,
    updatedAt: new Date(),
  });

  await logAuditEvent(db, {
    action: "storageUsage.reconcileRun",
    performedBy: actor.uid,
    performedByEmail: actor.email,
    targetType: "opsMetrics",
    targetId: "storageUsage",
    metadata: { ...stats },
  }).catch((e) => {
    console.error("[server-ops] audit log failed for storageUsage.reconcileRun", e);
  });

  return stats;
}
