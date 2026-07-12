import type { Firestore } from "firebase-admin/firestore";
import { z } from "zod";
import { logAuditEvent, ServerOpsValidationError, type Actor } from "./audit";

// /platformConfig/storageAlerts drives the amber/red states on the
// dashboard's audio-storage card. A missing doc means "no thresholds
// set" — the dashboard shows usage without alert states until a
// super-admin saves thresholds here. Thresholds compare against
// comprehension-audio bytes (the growth this exists to catch), not the
// whole bucket.
const ALERTS_COLLECTION = "platformConfig";
const ALERTS_DOC_ID = "storageAlerts";

const GIB = 1024 ** 3;
export const DEFAULT_WARN_BYTES = 5 * GIB;
export const DEFAULT_CRITICAL_BYTES = 20 * GIB;

const paramsSchema = z
  .object({
    warnBytes: z.number().int().positive(),
    criticalBytes: z.number().int().positive(),
  })
  .refine((p) => p.warnBytes < p.criticalBytes, {
    message: "Warn threshold must be below the critical threshold",
  });

export interface SetStorageAlertsConfigParams {
  warnBytes: number;
  criticalBytes: number;
}

export interface StorageAlertsConfig {
  // False until a super-admin has saved thresholds; the defaults below
  // are form prefills, not active alert levels.
  configured: boolean;
  warnBytes: number;
  criticalBytes: number;
  updatedAt: string | null;
  updatedBy?: string;
  updatedByEmail?: string;
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

export async function getStorageAlertsConfig(
  db: Firestore
): Promise<StorageAlertsConfig> {
  const snap = await db.collection(ALERTS_COLLECTION).doc(ALERTS_DOC_ID).get();
  const data = snap.data();
  if (!snap.exists || !data) {
    return {
      configured: false,
      warnBytes: DEFAULT_WARN_BYTES,
      criticalBytes: DEFAULT_CRITICAL_BYTES,
      updatedAt: null,
    };
  }
  return {
    configured:
      typeof data.warnBytes === "number" &&
      typeof data.criticalBytes === "number",
    warnBytes:
      typeof data.warnBytes === "number" ? data.warnBytes : DEFAULT_WARN_BYTES,
    criticalBytes:
      typeof data.criticalBytes === "number"
        ? data.criticalBytes
        : DEFAULT_CRITICAL_BYTES,
    updatedAt: toISO(data.updatedAt),
    updatedBy: data.updatedBy as string | undefined,
    updatedByEmail: data.updatedByEmail as string | undefined,
  };
}

export async function setStorageAlertsConfig(
  db: Firestore,
  actor: Actor,
  params: SetStorageAlertsConfigParams
): Promise<StorageAlertsConfig> {
  const parsed = paramsSchema.safeParse(params);
  if (!parsed.success) {
    throw new ServerOpsValidationError(
      parsed.error.issues[0]?.message ?? "Invalid storage alert thresholds"
    );
  }
  const { warnBytes, criticalBytes } = parsed.data;

  const payload: Record<string, unknown> = {
    warnBytes,
    criticalBytes,
    updatedAt: new Date(),
    updatedBy: actor.uid,
  };
  if (actor.email) payload.updatedByEmail = actor.email;

  await db
    .collection(ALERTS_COLLECTION)
    .doc(ALERTS_DOC_ID)
    .set(payload, { merge: true });

  await logAuditEvent(db, {
    action: "platformConfig.storageAlerts.update",
    performedBy: actor.uid,
    performedByEmail: actor.email,
    targetType: "platformConfig",
    targetId: ALERTS_DOC_ID,
    after: { warnBytes, criticalBytes },
  }).catch((e) => {
    console.error(
      "[server-ops] audit log failed for platformConfig.storageAlerts",
      e
    );
  });

  return getStorageAlertsConfig(db);
}
