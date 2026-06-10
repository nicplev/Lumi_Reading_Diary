import type { Firestore } from "firebase-admin/firestore";
import { z } from "zod";
import { logAuditEvent, ServerOpsValidationError, type Actor } from "./audit";

// /platformConfig/comprehensionRecording is the global kill switch for the
// comprehension voice-recording feature. A missing doc means "enabled" — the
// per-school settings.comprehensionRecording toggle stays the opt-in, this
// doc only ever force-disables it platform-wide. Clients read the doc
// directly; storage.rules also reads it to deny audio uploads from stale
// clients while the switch is off.
const FLAG_COLLECTION = "platformConfig";
const FLAG_DOC_ID = "comprehensionRecording";

const paramsSchema = z
  .object({
    enabled: z.boolean(),
    reason: z.string().trim().max(500).optional(),
  })
  .refine((p) => p.enabled || (p.reason && p.reason.length > 0), {
    message: "A reason is required when disabling comprehension recording",
    path: ["reason"],
  });

export interface SetComprehensionRecordingFlagParams {
  enabled: boolean;
  reason?: string;
}

export interface ComprehensionRecordingFlag {
  enabled: boolean;
  updatedAt: string | null;
  updatedBy?: string;
  updatedByEmail?: string;
  reason?: string;
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

export async function getComprehensionRecordingFlag(
  db: Firestore
): Promise<ComprehensionRecordingFlag> {
  const snap = await db.collection(FLAG_COLLECTION).doc(FLAG_DOC_ID).get();
  const data = snap.data();
  if (!snap.exists || !data) {
    return { enabled: true, updatedAt: null };
  }
  return {
    enabled: (data.enabled as boolean | undefined) ?? true,
    updatedAt: toISO(data.updatedAt),
    updatedBy: data.updatedBy as string | undefined,
    updatedByEmail: data.updatedByEmail as string | undefined,
    reason: data.reason as string | undefined,
  };
}

export async function setComprehensionRecordingFlag(
  db: Firestore,
  actor: Actor,
  params: SetComprehensionRecordingFlagParams
): Promise<ComprehensionRecordingFlag> {
  const parsed = paramsSchema.safeParse(params);
  if (!parsed.success) {
    throw new ServerOpsValidationError(
      parsed.error.issues[0]?.message ?? "Invalid input"
    );
  }
  const { enabled, reason } = parsed.data;

  const payload: Record<string, unknown> = {
    enabled,
    updatedAt: new Date(),
    updatedBy: actor.uid,
  };
  if (actor.email) payload.updatedByEmail = actor.email;
  if (reason) payload.reason = reason;

  // Full set (no merge): a stale reason from an earlier disable must not
  // linger after re-enabling.
  await db.collection(FLAG_COLLECTION).doc(FLAG_DOC_ID).set(payload);

  await logAuditEvent(db, {
    action: enabled
      ? "platformConfig.comprehensionRecording.enable"
      : "platformConfig.comprehensionRecording.disable",
    performedBy: actor.uid,
    performedByEmail: actor.email,
    targetType: "platformConfig",
    targetId: FLAG_DOC_ID,
    after: { enabled, ...(reason ? { reason } : {}) },
  }).catch((e) => {
    console.error(
      "[server-ops] audit log failed for platformConfig.comprehensionRecording",
      e
    );
  });

  return getComprehensionRecordingFlag(db);
}
