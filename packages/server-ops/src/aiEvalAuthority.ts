// MIRROR of the entitlement half of functions/src/ai_evaluation/gates.ts.
// Keep this file zero-import and update the parity test with every change.

export const AI_EVAL_AUTHORITY_VERSION = "school-ai-eval-v1-2026-07-20";

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object"
    ? (value as Record<string, unknown>)
    : {};
}

export function platformAiEvaluationEnabled(data: unknown): boolean {
  return asRecord(data).enabled === true;
}

export function schoolAiEvaluationEnabled(school: unknown): boolean {
  const settings = asRecord(asRecord(school).settings);
  const ai = asRecord(settings.aiEvaluation);
  return (
    ai.enabled === true &&
    ai.authorityVersion === AI_EVAL_AUTHORITY_VERSION &&
    ai.authorityConfirmedAt != null
  );
}
