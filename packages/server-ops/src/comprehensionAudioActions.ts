import type {
  DocumentReference,
  Firestore,
  Query,
} from "firebase-admin/firestore";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import type { Storage } from "firebase-admin/storage";
import { z } from "zod";
import { logAuditEvent, ServerOpsValidationError, type Actor } from "./audit";
import {
  MAX_RETENTION_DAYS,
  MIN_RETENTION_DAYS,
} from "./setComprehensionRetentionConfig";

// Manual cleanup helpers for comprehension audio. Used by the super-admin
// portal (Run Now), the school-admin portal (bulk delete + preview), and the
// teacher single-delete callable.
//
// The scheduled cron in functions/src/comprehension_retention.ts intentionally
// keeps its own copy of the cleanup loop — functions/ doesn't depend on the
// server-ops workspace package, so trying to share via import would entangle
// the deploy bundle. The duplication is contained to ~30 lines and both
// implementations are covered by integration tests.

const RETENTION_DOC = "platformConfig/comprehensionRetention";
const BATCH_SIZE = 500;
const DAY_MS = 86_400_000;
// Safety cap: the page loop yields the same expired docs until they're
// patched, so a per-batch failure must not loop forever. 50 × 500 = 25k is
// well beyond any plausible 24-hour backlog.
const MAX_PAGES = 50;

// Tags audit-log entries so an operator can tell whether a deletion came
// from a teacher, the bulk admin tool, or one of the retention runs.
export type ComprehensionDeleteSource =
  | "manualTeacher"
  | "manualSchoolAdmin"
  | "manualSuperAdmin"
  | "manualSchoolAdminBulk";

async function deleteStorageObjectIfExists(
  storage: Storage,
  path: string
): Promise<void> {
  try {
    await storage.bucket().file(path).delete();
  } catch (err: unknown) {
    const code = (err as { code?: number }).code;
    if (code === 404) return;
    throw err;
  }
}

// Core mutation: deletes the Storage object (if present), then patches the
// log doc to clear the audio fields and stamp a tombstone. Does NOT write to
// adminAuditLog — callers decide the granularity (one entry per click, vs
// one summary entry per bulk).
async function deleteOneCore(args: {
  storage: Storage;
  logRef: DocumentReference;
  storagePath: string | undefined;
}): Promise<void> {
  if (args.storagePath) {
    await deleteStorageObjectIfExists(args.storage, args.storagePath);
  }
  await args.logRef.update({
    comprehensionAudioPath: FieldValue.delete(),
    comprehensionAudioDurationSec: FieldValue.delete(),
    comprehensionAudioUploaded: false,
    comprehensionAudioDeletedAt: FieldValue.serverTimestamp(),
  });
}

// =============================================================================
// 1. Single delete (teacher trash button, school-admin row trash button)
// =============================================================================

const deleteOneParamsSchema = z.object({
  schoolId: z.string().min(1),
  logId: z.string().min(1),
});

export interface DeleteOneComprehensionAudioParams {
  schoolId: string;
  logId: string;
  actor: Actor;
  source: ComprehensionDeleteSource;
}

export interface DeleteOneComprehensionAudioResult {
  deleted: boolean;
  reason?: "no_audio";
}

export async function deleteOneComprehensionAudio(
  db: Firestore,
  storage: Storage,
  params: DeleteOneComprehensionAudioParams
): Promise<DeleteOneComprehensionAudioResult> {
  const parsed = deleteOneParamsSchema.safeParse({
    schoolId: params.schoolId,
    logId: params.logId,
  });
  if (!parsed.success) {
    throw new ServerOpsValidationError(
      parsed.error.issues[0]?.message ?? "Invalid input"
    );
  }
  const logRef = db
    .collection("schools")
    .doc(params.schoolId)
    .collection("readingLogs")
    .doc(params.logId);
  const snap = await logRef.get();
  if (!snap.exists) {
    throw new ServerOpsValidationError("Reading log not found");
  }
  const data = snap.data() ?? {};
  if (data.comprehensionAudioUploaded !== true) {
    return { deleted: false, reason: "no_audio" };
  }
  const storagePath = data.comprehensionAudioPath as string | undefined;

  await deleteOneCore({ storage, logRef, storagePath });

  await logAuditEvent(db, {
    action: "comprehensionAudio.manualDelete",
    performedBy: params.actor.uid,
    performedByEmail: params.actor.email,
    targetType: "readingLog",
    targetId: params.logId,
    schoolId: params.schoolId,
    metadata: { source: params.source, storagePath },
  }).catch((e) =>
    console.error("[server-ops] audit log failed for manualDelete", e)
  );

  return { deleted: true };
}

// =============================================================================
// 2. School-admin bulk delete: date range (+ optional classId)
// =============================================================================

const bulkParamsSchema = z
  .object({
    schoolId: z.string().min(1),
    startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    classId: z.string().min(1).optional(),
  })
  .refine((p) => p.startDate <= p.endDate, {
    message: "startDate must be on or before endDate",
    path: ["startDate"],
  });

export interface BulkComprehensionAudioFilter {
  schoolId: string;
  startDate: string; // YYYY-MM-DD inclusive
  endDate: string; // YYYY-MM-DD inclusive
  classId?: string;
}

function buildReadingLogsQuery(
  db: Firestore,
  filter: BulkComprehensionAudioFilter
): Query {
  // The reading-log `date` field is a Timestamp set by the parent app at
  // log-submit time. Day boundaries are treated as UTC here — v1 doesn't
  // account for ANZ-timezone day shifts (acceptable: the school admin sees
  // the same UTC-ish dates in the existing logs UI).
  const startMs = Date.parse(`${filter.startDate}T00:00:00.000Z`);
  const endMs = Date.parse(`${filter.endDate}T23:59:59.999Z`);
  let q: Query = db
    .collection("schools")
    .doc(filter.schoolId)
    .collection("readingLogs")
    .where("comprehensionAudioUploaded", "==", true)
    .where("date", ">=", Timestamp.fromMillis(startMs))
    .where("date", "<=", Timestamp.fromMillis(endMs));
  if (filter.classId) {
    q = q.where("classId", "==", filter.classId);
  }
  return q;
}

export async function previewComprehensionAudioCount(
  db: Firestore,
  filter: BulkComprehensionAudioFilter
): Promise<{ count: number }> {
  const parsed = bulkParamsSchema.safeParse({ ...filter });
  if (!parsed.success) {
    throw new ServerOpsValidationError(
      parsed.error.issues[0]?.message ?? "Invalid filter"
    );
  }
  const agg = await buildReadingLogsQuery(db, filter).count().get();
  return { count: agg.data().count };
}

export interface BulkComprehensionAudioResult {
  deletedCount: number;
  failedCount: number;
}

export async function bulkDeleteComprehensionAudio(
  db: Firestore,
  storage: Storage,
  filter: BulkComprehensionAudioFilter,
  actor: Actor
): Promise<BulkComprehensionAudioResult> {
  const parsed = bulkParamsSchema.safeParse({ ...filter });
  if (!parsed.success) {
    throw new ServerOpsValidationError(
      parsed.error.issues[0]?.message ?? "Invalid filter"
    );
  }

  let deletedCount = 0;
  let failedCount = 0;

  for (let page = 0; page < MAX_PAGES; page++) {
    const snap = await buildReadingLogsQuery(db, filter).limit(BATCH_SIZE).get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      const data = doc.data();
      const storagePath = data.comprehensionAudioPath as string | undefined;
      try {
        await deleteOneCore({ storage, logRef: doc.ref, storagePath });
        deletedCount++;
      } catch (err) {
        failedCount++;
        console.error(
          "[server-ops] bulkDeleteComprehensionAudio: per-doc failure",
          {
            logPath: doc.ref.path,
            storagePath,
            error: err instanceof Error ? err.message : String(err),
          }
        );
      }
    }
    if (snap.size < BATCH_SIZE) break;
  }

  await logAuditEvent(db, {
    action: "comprehensionAudio.bulkDelete",
    performedBy: actor.uid,
    performedByEmail: actor.email,
    targetType: "school",
    targetId: filter.schoolId,
    schoolId: filter.schoolId,
    metadata: {
      startDate: filter.startDate,
      endDate: filter.endDate,
      classId: filter.classId ?? null,
      deletedCount,
      failedCount,
    },
  }).catch((e) =>
    console.error("[server-ops] audit failed for bulkDelete summary", e)
  );

  return { deletedCount, failedCount };
}

// =============================================================================
// 3. Super-admin Run-Now: same cleanup the cron does, attributed to a real
//    operator instead of the system principal
// =============================================================================

interface RetentionConfigDoc {
  enabled?: boolean;
  retentionDays?: number;
}

export interface RunRetentionNowStats {
  deletedCount: number;
  failedCount: number;
  durationMs: number;
  cutoffISO: string;
  retentionDays: number;
}

export type RunRetentionNowOutcome =
  | { skipped: true; reason: string }
  | ({ skipped?: false } & RunRetentionNowStats);

export async function runComprehensionRetentionNow(
  db: Firestore,
  storage: Storage,
  actor: Actor
): Promise<RunRetentionNowOutcome> {
  const startedAtMs = Date.now();
  const configSnap = await db.doc(RETENTION_DOC).get();
  const config = configSnap.data() as RetentionConfigDoc | undefined;
  if (!configSnap.exists || !config) {
    return { skipped: true, reason: "config_missing" };
  }
  if (config.enabled !== true) {
    return { skipped: true, reason: "disabled" };
  }
  const retentionDays = config.retentionDays ?? 0;
  if (
    !Number.isInteger(retentionDays) ||
    retentionDays < MIN_RETENTION_DAYS ||
    retentionDays > MAX_RETENTION_DAYS
  ) {
    return { skipped: true, reason: "invalid_retentionDays" };
  }

  const cutoff = Timestamp.fromMillis(startedAtMs - retentionDays * DAY_MS);
  const cutoffISO = cutoff.toDate().toISOString();

  let deletedCount = 0;
  let failedCount = 0;

  for (let page = 0; page < MAX_PAGES; page++) {
    const snap = await db
      .collectionGroup("readingLogs")
      .where("comprehensionAudioUploaded", "==", true)
      .where("createdAt", "<", cutoff)
      .limit(BATCH_SIZE)
      .get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      const data = doc.data();
      const storagePath = data.comprehensionAudioPath as string | undefined;
      try {
        await deleteOneCore({ storage, logRef: doc.ref, storagePath });
        deletedCount++;
      } catch (err) {
        failedCount++;
        console.error(
          "[server-ops] runComprehensionRetentionNow: per-doc failure",
          {
            logPath: doc.ref.path,
            storagePath,
            error: err instanceof Error ? err.message : String(err),
          }
        );
      }
    }
    if (snap.size < BATCH_SIZE) break;
  }

  const stats: RunRetentionNowStats = {
    deletedCount,
    failedCount,
    durationMs: Date.now() - startedAtMs,
    cutoffISO,
    retentionDays,
  };

  await db.doc(RETENTION_DOC).set(
    {
      lastRunAt: new Date(),
      lastRunStats: stats,
    },
    { merge: true }
  );
  await logAuditEvent(db, {
    action: "comprehensionAudio.retentionRun",
    performedBy: actor.uid,
    performedByEmail: actor.email,
    targetType: "platformConfig",
    targetId: "comprehensionRetention",
    metadata: { ...stats, source: "manualSuperAdmin" },
  }).catch((e) =>
    console.error("[server-ops] audit failed for runRetentionNow", e)
  );

  return stats;
}
