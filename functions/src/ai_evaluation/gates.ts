// AI evaluation feature gates (Phase 2).
//
// EVERY gate here fails CLOSED: a missing document, malformed data or a
// read error means the feature is OFF. This is deliberately the opposite
// of the platformConfig missing-doc-means-enabled house convention used
// by the recording flag — do not reuse those helpers for AI gating.

export const AI_EVALUATION_FLAG_DOC = "platformConfig/aiEvaluation";

// Versioned evidence that a school agreed to AI evaluation specifically —
// the analogue of AUDIO_AUTHORITY_VERSION for audio collection. Bump this
// when the terms materially change; every school then falls out of
// entitlement until a super-admin re-confirms against the new version,
// which is the point.
//
// Before 2026-07-20 the entitlement was a bare `enabled === true`. The
// writer demanded a non-empty `termsVersionAccepted`, but it was a free-text
// box, so any string satisfied it — the live prod value for the pilot school
// was literally the field's own label, "Terms version accepted". That is a
// formality, not evidence. The gate now requires the canonical version plus
// a server-stamped confirmation time.
export const AI_EVAL_AUTHORITY_VERSION = "school-ai-eval-v1-2026-07-20";

// Narrows an unknown value to a plain record.
function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" ?
    (value as Record<string, unknown>) :
    {};
}

// Platform kill switch predicate for `platformConfig/aiEvaluation`.
// Only the literal `{enabled: true}` opens the gate.
export function platformAiEvaluationEnabled(data: unknown): boolean {
  return asRecord(data).enabled === true;
}

// Per-school entitlement predicate for `school.settings.aiEvaluation`.
// The entitlement is written only by the super-admin portal; clients are
// blocked from touching it by firestore.rules.
//
// Requires all three: the switch, the CURRENT authority version, and a
// confirmation timestamp. Fails closed on anything else.
export function schoolAiEvaluationEnabled(school: unknown): boolean {
  const settings = asRecord(asRecord(school).settings);
  const ai = asRecord(settings.aiEvaluation);
  return ai.enabled === true &&
    ai.authorityVersion === AI_EVAL_AUTHORITY_VERSION &&
    ai.authorityConfirmedAt != null;
}
