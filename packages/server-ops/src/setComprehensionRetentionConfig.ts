import type { Firestore } from "firebase-admin/firestore";
import { z } from "zod";
import { logAuditEvent, ServerOpsValidationError, type Actor } from "./audit";

// /platformConfig/comprehensionRetention drives the scheduled cleanup job for
// comprehension audio recordings. Held as a sibling doc to
// platformConfig/comprehensionRecording (the kill switch) rather than inside
// it, because the kill-switch writer does a full .set without merge to flush
// the stale `reason` field on re-enable, which would otherwise wipe retention
// fields on every toggle.
//
// A missing doc means "retention disabled" — no cleanup runs and storage
// grows unbounded. The mobile client never reads this doc; only the cron and
// the super-admin UI do.
const RETENTION_COLLECTION = "platformConfig";
const RETENTION_DOC_ID = "comprehensionRetention";

export const MIN_RETENTION_DAYS = 7;
export const MAX_RETENTION_DAYS = 730;
export const DEFAULT_RETENTION_DAYS = 90;

const paramsSchema = z.object({
  enabled: z.boolean(),
  retentionDays: z
    .number()
    .int()
    .min(MIN_RETENTION_DAYS)
    .max(MAX_RETENTION_DAYS),
});

export interface SetComprehensionRetentionConfigParams {
  enabled: boolean;
  retentionDays: number;
}

export interface ComprehensionRetentionRunStats {
  deletedCount: number;
  failedCount: number;
  durationMs: number;
  cutoffISO: string;
}

export interface ComprehensionRetentionConfig {
  enabled: boolean;
  retentionDays: number;
  updatedAt: string | null;
  updatedBy?: string;
  updatedByEmail?: string;
  lastRunAt: string | null;
  lastRunStats: ComprehensionRetentionRunStats | null;
}

function toISO(ts: unknown): string | null {
  if (!ts || typeof ts !== "object") return null;
  if (
    "toDate" in ts &&
    typeof (ts as { toDate: unknown }).toDate === "function"
  ) {
    return (ts as { toDate: () => Date }).toDate().toISOString();
  }
  return null;
}

function readRunStats(raw: unknown): ComprehensionRetentionRunStats | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  const deletedCount = typeof r.deletedCount === "number" ? r.deletedCount : null;
  const failedCount = typeof r.failedCount === "number" ? r.failedCount : null;
  const durationMs = typeof r.durationMs === "number" ? r.durationMs : null;
  const cutoffISO = typeof r.cutoffISO === "string" ? r.cutoffISO : null;
  if (
    deletedCount === null ||
    failedCount === null ||
    durationMs === null ||
    cutoffISO === null
  ) {
    return null;
  }
  return { deletedCount, failedCount, durationMs, cutoffISO };
}

export async function getComprehensionRetentionConfig(
  db: Firestore
): Promise<ComprehensionRetentionConfig> {
  const snap = await db.collection(RETENTION_COLLECTION).doc(RETENTION_DOC_ID).get();
  const data = snap.data();
  if (!snap.exists || !data) {
    return {
      enabled: false,
      retentionDays: DEFAULT_RETENTION_DAYS,
      updatedAt: null,
      lastRunAt: null,
      lastRunStats: null,
    };
  }
  const retentionDaysRaw = data.retentionDays;
  return {
    enabled: (data.enabled as boolean | undefined) ?? false,
    retentionDays:
      typeof retentionDaysRaw === "number" && Number.isInteger(retentionDaysRaw)
        ? retentionDaysRaw
        : DEFAULT_RETENTION_DAYS,
    updatedAt: toISO(data.updatedAt),
    updatedBy: data.updatedBy as string | undefined,
    updatedByEmail: data.updatedByEmail as string | undefined,
    lastRunAt: toISO(data.lastRunAt),
    lastRunStats: readRunStats(data.lastRunStats),
  };
}

export async function setComprehensionRetentionConfig(
  db: Firestore,
  actor: Actor,
  params: SetComprehensionRetentionConfigParams
): Promise<ComprehensionRetentionConfig> {
  const parsed = paramsSchema.safeParse(params);
  if (!parsed.success) {
    throw new ServerOpsValidationError(
      parsed.error.issues[0]?.message ?? "Invalid retention config"
    );
  }
  const { enabled, retentionDays } = parsed.data;

  const payload: Record<string, unknown> = {
    enabled,
    retentionDays,
    updatedAt: new Date(),
    updatedBy: actor.uid,
  };
  if (actor.email) payload.updatedByEmail = actor.email;

  // Merge: we must preserve lastRunAt and lastRunStats which are written by
  // the cron, not the operator. The kill-switch doc next door uses .set()
  // without merge for a different reason (clearing stale `reason`) — that
  // concern does not apply here.
  await db
    .collection(RETENTION_COLLECTION)
    .doc(RETENTION_DOC_ID)
    .set(payload, { merge: true });

  await logAuditEvent(db, {
    action: "platformConfig.comprehensionRetention.update",
    performedBy: actor.uid,
    performedByEmail: actor.email,
    targetType: "platformConfig",
    targetId: RETENTION_DOC_ID,
    after: { enabled, retentionDays },
  }).catch((e) => {
    console.error(
      "[server-ops] audit log failed for platformConfig.comprehensionRetention",
      e
    );
  });

  return getComprehensionRetentionConfig(db);
}
