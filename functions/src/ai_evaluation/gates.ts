// AI evaluation feature gates (Phase 2).
//
// EVERY gate here fails CLOSED: a missing document, malformed data or a
// read error means the feature is OFF. This is deliberately the opposite
// of the platformConfig missing-doc-means-enabled house convention used
// by the recording flag — do not reuse those helpers for AI gating.

export const AI_EVALUATION_FLAG_DOC = "platformConfig/aiEvaluation";

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
export function schoolAiEvaluationEnabled(school: unknown): boolean {
  const settings = asRecord(asRecord(school).settings);
  return asRecord(settings.aiEvaluation).enabled === true;
}
