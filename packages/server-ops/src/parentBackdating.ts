import { FieldValue, type Firestore } from "firebase-admin/firestore";
import { z } from "zod";
import { logAuditEvent, ServerOpsValidationError, type Actor } from "./audit";

// Parent Yesterday-backdating switch (super-admin portal only).
//
// Decision D1 of docs/PARENT_LOGGING_FLOW_PLAN.md: parents may record a
// session for Yesterday (never further back) in the app's detailed logging
// flow. Nic approved it for first-round school testing ON CONDITION that it
// can be turned off without an app release, based on real evidence — this
// flag is that lever, and the `backdated_session` analytics counter is the
// evidence.
//
// ⚠ THIS FLAG FAILS **OPEN**, like coverOcr and unlike aiEvaluation: a
// missing document, malformed document or read error all mean ENABLED;
// only a literal `enabled: false` turns the affordance off. Deliberate —
// the feature ships on for the testing round, and an unrelated Firestore
// blip must not silently remove it mid-beta.
//
// PARITY CONTRACT: the only other resolver of this document is the Flutter
// client — `isParentBackdatingEnabled()` in
// lib/services/platform_config_service.dart, which resolves
// `!doc.exists || data['enabled'] != false` (≈5-min client cache, and a
// read failure falls back to the last cached value, then true). The
// resolver below MUST keep identical semantics: if the portal and the app
// disagreed, this card would display a state the feature is not in.
// test/parentBackdating.test.ts pins the fixture behaviour.

const FLAG_PATH = "platformConfig/parentBackdating";

export interface ParentBackdatingFlag {
  enabled: boolean;
  /** False when no document exists yet — enabled is then a default, not a choice. */
  configured: boolean;
  updatedAt: string | null;
  updatedBy?: string;
  updatedByEmail?: string;
  reason?: string;
}

function toISO(value: unknown): string | null {
  if (!value || typeof value !== "object") return null;
  const anyValue = value as { toDate?: () => Date };
  if (typeof anyValue.toDate === "function") {
    return anyValue.toDate().toISOString();
  }
  return null;
}

/**
 * Resolves the flag document to on/off. Mirrors the Flutter client's
 * `isParentBackdatingEnabled` (see parity contract above): everything is
 * ENABLED except a document whose `enabled` is literally `false`.
 */
export function parentBackdatingEnabledFromDoc(data: unknown): boolean {
  if (!data || typeof data !== "object" || Array.isArray(data)) return true;
  return (data as Record<string, unknown>).enabled !== false;
}

export async function getParentBackdatingFlag(
  db: Firestore
): Promise<ParentBackdatingFlag> {
  const snap = await db.doc(FLAG_PATH).get();
  const raw = snap.data();
  const data = raw ?? {};
  return {
    enabled: parentBackdatingEnabledFromDoc(raw),
    configured: snap.exists,
    updatedAt: toISO(data.updatedAt),
    updatedBy: typeof data.updatedBy === "string" ? data.updatedBy : undefined,
    updatedByEmail:
      typeof data.updatedByEmail === "string" ? data.updatedByEmail : undefined,
    reason: typeof data.reason === "string" ? data.reason : undefined,
  };
}

const flagParams = z.object({
  enabled: z.boolean(),
  reason: z.string().trim().max(500).optional(),
});

export async function setParentBackdatingFlag(
  db: Firestore,
  actor: Actor,
  params: { enabled: boolean; reason?: string }
): Promise<ParentBackdatingFlag> {
  const parsed = flagParams.safeParse(params);
  if (!parsed.success) {
    throw new ServerOpsValidationError("Invalid parent backdating flag input");
  }
  if (!parsed.data.enabled && !parsed.data.reason) {
    throw new ServerOpsValidationError(
      "A reason is required when turning parent backdating off platform-wide"
    );
  }
  // Full set (no merge) so a stale `reason` never survives a re-enable —
  // mirrors the coverOcr/aiEvaluation/comprehensionRecording writers.
  await db.doc(FLAG_PATH).set({
    enabled: parsed.data.enabled,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: actor.uid,
    ...(actor.email ? { updatedByEmail: actor.email } : {}),
    ...(parsed.data.reason ? { reason: parsed.data.reason } : {}),
  });
  await logAuditEvent(db, {
    action: parsed.data.enabled
      ? "parent_backdating_enabled"
      : "parent_backdating_disabled",
    performedBy: actor.uid,
    performedByEmail: actor.email,
    targetType: "platformConfig",
    targetId: "parentBackdating",
    metadata: parsed.data.reason ? { reason: parsed.data.reason } : {},
  });
  return getParentBackdatingFlag(db);
}
