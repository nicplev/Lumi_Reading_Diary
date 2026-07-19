// Comprehension question snapshot helpers (Phase 2).
//
// The per-class question lives at classes/{classId}.settings.comprehensionQuestion
// and is captured onto the reading log at audio-confirm time so a later
// evaluation scores the answer against the question the child actually heard,
// even if the teacher edits the class question afterwards.

// Mirror of ClassModel.defaultComprehensionQuestion in the app.
export const DEFAULT_COMPREHENSION_QUESTION =
  "Tell us about what you read tonight.";

// Mirror of the teacher editor's client-side clamp.
export const MAX_COMPREHENSION_QUESTION_CHARS = 200;

// Narrows an unknown value to a plain record.
function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" ?
    (value as Record<string, unknown>) :
    {};
}

// Normalises a raw question value: trims, falls back to the default when
// empty or non-string, and re-clamps to the 200-character limit so a
// malformed class doc can never bloat reading-log documents.
export function clampComprehensionQuestion(raw: unknown): string {
  const text = typeof raw === "string" ? raw.trim() : "";
  if (!text) return DEFAULT_COMPREHENSION_QUESTION;
  if (text.length <= MAX_COMPREHENSION_QUESTION_CHARS) return text;
  return text.slice(0, MAX_COMPREHENSION_QUESTION_CHARS);
}

// Extracts and clamps the current question from a class document.
export function classComprehensionQuestion(classData: unknown): string {
  const settings = asRecord(asRecord(classData).settings);
  return clampComprehensionQuestion(settings.comprehensionQuestion);
}
