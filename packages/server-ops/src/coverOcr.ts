import { FieldValue, type Firestore } from "firebase-admin/firestore";
import { z } from "zod";
import { logAuditEvent, ServerOpsValidationError, type Actor } from "./audit";

// Book-cover OCR kill switch (super-admin portal only).
//
// ⚠ THIS FLAG FAILS **OPEN**, unlike aiEvaluation next to it on the same
// page. A missing document, a malformed document or a read error all mean
// ENABLED; only the literal `enabled: false` closes the gate. That is
// deliberate — cover OCR reads a book jacket to pre-fill a catalog title and
// author, touches no student data, and must not break because of an
// unrelated Firestore blip. Do not "fix" this to match aiEvaluation: the
// server (functions/src/book_cover_ocr.ts) resolves it the same way, and
// making only one side fail-closed would silently disable the feature.
//
// `configured` exists so the UI can distinguish "on because someone turned
// it on" from "on because nothing has ever been written". Rendering those
// identically would let a missing doc read as a deliberate choice.

const FLAG_PATH = "platformConfig/coverOcr";

export interface CoverOcrFlag {
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
 * Resolves the flag document to on/off.
 *
 * MUST stay identical to `coverOcrEnabledFromDoc` in
 * functions/src/book_cover_ocr.ts — if the portal and the server disagreed,
 * the card would show a state the feature isn't actually in. Enforced by
 * test/coverOcr.parity.test.ts, which runs both over the same fixtures.
 */
export function coverOcrEnabledFromDoc(data: unknown): boolean {
  if (!data || typeof data !== "object" || Array.isArray(data)) return true;
  return (data as Record<string, unknown>).enabled !== false;
}

export async function getCoverOcrFlag(db: Firestore): Promise<CoverOcrFlag> {
  const snap = await db.doc(FLAG_PATH).get();
  const raw = snap.data();
  // Resolve from the raw value (undefined when the doc is absent) so the
  // parity contract above sees exactly what the server would.
  const data = raw ?? {};
  return {
    enabled: coverOcrEnabledFromDoc(raw),
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

export async function setCoverOcrFlag(
  db: Firestore,
  actor: Actor,
  params: { enabled: boolean; reason?: string }
): Promise<CoverOcrFlag> {
  const parsed = flagParams.safeParse(params);
  if (!parsed.success) {
    throw new ServerOpsValidationError("Invalid cover OCR flag input");
  }
  if (!parsed.data.enabled && !parsed.data.reason) {
    throw new ServerOpsValidationError(
      "A reason is required when disabling cover OCR platform-wide"
    );
  }
  // Full set (no merge) so a stale `reason` never survives a re-enable —
  // mirrors the aiEvaluation and comprehensionRecording writers.
  await db.doc(FLAG_PATH).set({
    enabled: parsed.data.enabled,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: actor.uid,
    ...(actor.email ? { updatedByEmail: actor.email } : {}),
    ...(parsed.data.reason ? { reason: parsed.data.reason } : {}),
  });
  await logAuditEvent(db, {
    action: parsed.data.enabled
      ? "cover_ocr_platform_enabled"
      : "cover_ocr_platform_disabled",
    performedBy: actor.uid,
    performedByEmail: actor.email,
    targetType: "platformConfig",
    targetId: "coverOcr",
    metadata: parsed.data.reason ? { reason: parsed.data.reason } : {},
  });
  return getCoverOcrFlag(db);
}
