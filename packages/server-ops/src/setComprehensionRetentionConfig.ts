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
// Automatic cleanup is always active. A missing/legacy-invalid doc uses the
// 90-day fallback so an operational toggle cannot suspend a school's recorded
// deletion commitment. The mobile client never reads this doc.
const RETENTION_COLLECTION = "platformConfig";
const RETENTION_DOC_ID = "comprehensionRetention";

export const MIN_RETENTION_DAYS = 30;
export const MAX_RETENTION_DAYS = 730;
export const DEFAULT_RETENTION_DAYS = 90;

const paramsSchema = z.object({
  retentionDays: z
    .number()
    .int()
    .min(MIN_RETENTION_DAYS)
    .max(MAX_RETENTION_DAYS),
});

export interface SetComprehensionRetentionConfigParams {
  retentionDays: number;
}

export interface ComprehensionRetentionRunStats {
  deletedCount: number;
  failedCount: number;
  durationMs: number;
  schoolCount?: number;
  legacyDefaultRetentionDays?: number;
  retentionPolicyCounts?: Record<string, number>;
  fallbackSchoolCount?: number;
  legacySevenDaySchoolCount?: number;
  trigger?: "cron" | "manual";
  cutoffISO?: string;
  retentionDays?: number;
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

export function readComprehensionRetentionRunStats(
  raw: unknown
): ComprehensionRetentionRunStats | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  const requiredNumber = (value: unknown): number | null =>
    typeof value === "number" && Number.isFinite(value) ? value : null;
  const deletedCount = requiredNumber(r.deletedCount);
  const failedCount = requiredNumber(r.failedCount);
  const durationMs = requiredNumber(r.durationMs);
  if (
    deletedCount === null ||
    failedCount === null ||
    durationMs === null
  ) {
    return null;
  }
  const optionalNumber = (key: string): number | undefined =>
    typeof r[key] === "number" && Number.isFinite(r[key])
      ? r[key] as number
      : undefined;
  const countsRaw = r.retentionPolicyCounts;
  const retentionPolicyCounts = countsRaw && typeof countsRaw === "object"
    ? Object.fromEntries(
        Object.entries(countsRaw).filter(
          ([, value]) => typeof value === "number" && Number.isFinite(value)
        )
      )
    : undefined;
  const trigger = r.trigger === "cron" || r.trigger === "manual"
    ? r.trigger
    : undefined;
  return {
    deletedCount,
    failedCount,
    durationMs,
    schoolCount: optionalNumber("schoolCount"),
    legacyDefaultRetentionDays: optionalNumber("legacyDefaultRetentionDays"),
    retentionPolicyCounts,
    fallbackSchoolCount: optionalNumber("fallbackSchoolCount"),
    legacySevenDaySchoolCount: optionalNumber("legacySevenDaySchoolCount"),
    trigger,
    cutoffISO: typeof r.cutoffISO === "string" ? r.cutoffISO : undefined,
    retentionDays: optionalNumber("retentionDays"),
  };
}

export async function getComprehensionRetentionConfig(
  db: Firestore
): Promise<ComprehensionRetentionConfig> {
  const snap = await db.collection(RETENTION_COLLECTION).doc(RETENTION_DOC_ID).get();
  const data = snap.data();
  if (!snap.exists || !data) {
    return {
      enabled: true,
      retentionDays: DEFAULT_RETENTION_DAYS,
      updatedAt: null,
      lastRunAt: null,
      lastRunStats: null,
    };
  }
  const retentionDaysRaw = data.retentionDays;
  return {
    enabled: true,
    retentionDays:
      typeof retentionDaysRaw === "number" &&
      Number.isInteger(retentionDaysRaw) &&
      retentionDaysRaw >= MIN_RETENTION_DAYS &&
      retentionDaysRaw <= MAX_RETENTION_DAYS
        ? retentionDaysRaw
        : DEFAULT_RETENTION_DAYS,
    updatedAt: toISO(data.updatedAt),
    updatedBy: data.updatedBy as string | undefined,
    updatedByEmail: data.updatedByEmail as string | undefined,
    lastRunAt: toISO(data.lastRunAt),
    lastRunStats: readComprehensionRetentionRunStats(data.lastRunStats),
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
  const { retentionDays } = parsed.data;

  const payload: Record<string, unknown> = {
    enabled: true,
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
    after: { enabled: true, retentionDays },
  }).catch((e) => {
    console.error(
      "[server-ops] audit log failed for platformConfig.comprehensionRetention",
      e
    );
  });

  return getComprehensionRetentionConfig(db);
}
