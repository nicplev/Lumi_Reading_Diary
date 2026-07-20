// Response schemas + server-side re-validation (Phase 3 — dark).
//
// The Vertex responseSchema constrains decoding, but constrained decoding
// is never trusted as validation: every provider response is re-validated
// here before anything is written to Firestore. Unknown flags/criteria are
// dropped, scores clamped, strings truncated — the model can never widen
// the stored vocabulary.

import {QUESTION_CATEGORIES, Rubric} from "./rubrics";

export const OVERALL_LEVELS: readonly string[] = [
  "not_evident", "emerging", "developing", "secure",
];
export const CONFIDENCE_LEVELS: readonly string[] = ["low", "medium", "high"];

// Flags the MODEL is allowed to raise (enum-constrained in the schema).
export const MODEL_FLAGS: readonly string[] = [
  "off_topic",
  "non_english",
  "question_mismatch",
  "prompt_injection",
  "adult_prompting",
  "empty_response",
  "unsupported_self_assessment",
  "incidental_personal_info",
];

// Flags only the WORKER may set (never offered to the model).
export const WORKER_FLAGS: readonly string[] = [
  "too_short",
  "inaudible",
  "low_stt_confidence",
  "concerning_content",
  "recitation_blocked",
  "audio_unavailable",
  "system_error",
];

export const MAX_SUMMARY_CHARS = 700;
// Safety nets only - the prompt asks for a <=15 word span. The model
// mostly complies but occasionally quotes a whole passage instead, so we
// clamp on words first (the limit the prompt states) and chars second (a
// backstop against one absurdly long "word"). A visibly clipped quote is
// the signal we want the teacher, and us, to notice.
export const MAX_EVIDENCE_WORDS = 18;
export const MAX_EVIDENCE_CHARS = 200;
export const MIN_CRITERION_SCORE = 0;
export const MAX_CRITERION_SCORE = 3;

// Vertex structured-output schema (OpenAPI subset, uppercase types).
// propertyOrdering puts evidence before the level so the level is decoded
// after the evidence — ordering-as-reasoning, free.
// NOTE: this schema counts toward input tokens; keep it lean.
export const EVAL_RESPONSE_SCHEMA = {
  type: "OBJECT",
  properties: {
    summary: {type: "STRING"},
    criterionScores: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          criterionId: {type: "STRING"},
          score: {type: "INTEGER"},
          evidence: {
            type: "STRING",
            description: "Shortest verbatim span from the transcript " +
              "showing this criterion. Hard limit 15 words, max one " +
              "sentence; a fragment is preferred. Empty if nothing " +
              "supports it.",
          },
        },
        required: ["criterionId", "score", "evidence"],
      },
    },
    overallLevel: {type: "STRING", enum: [...OVERALL_LEVELS]},
    confidence: {type: "STRING", enum: [...CONFIDENCE_LEVELS]},
    flags: {type: "ARRAY", items: {type: "STRING", enum: [...MODEL_FLAGS]}},
    assessable: {type: "BOOLEAN"},
  },
  required: [
    "summary", "criterionScores", "overallLevel", "confidence", "flags",
    "assessable",
  ],
  propertyOrdering: [
    "summary", "criterionScores", "overallLevel", "confidence", "flags",
    "assessable",
  ],
};

export const CLASSIFICATION_RESPONSE_SCHEMA = {
  type: "OBJECT",
  properties: {
    categories: {
      type: "ARRAY",
      items: {type: "STRING", enum: [...QUESTION_CATEGORIES]},
    },
  },
  required: ["categories"],
};

export interface ValidatedCriterionScore {
  criterionId: string;
  score: number;
  evidence: string;
}

export interface ValidatedEvalResponse {
  summary: string;
  criterionScores: ValidatedCriterionScore[];
  overallLevel: string;
  confidence: string;
  flags: string[];
  assessable: boolean;
}

export type EvalValidation =
  | {ok: true, value: ValidatedEvalResponse}
  | {ok: false, reason: string};

function truncate(value: string, max: number): string {
  return value.length <= max ? value : value.slice(0, max);
}

// Clips an evidence quote to the word limit the prompt states, then to a
// char backstop, marking the cut so it reads as "quote, truncated" rather
// than a word sliced in half.
function clampEvidence(value: string): string {
  let out = value;
  let clipped = false;

  const words = out.split(/\s+/);
  if (words.length > MAX_EVIDENCE_WORDS) {
    out = words.slice(0, MAX_EVIDENCE_WORDS).join(" ");
    clipped = true;
  }
  if (out.length > MAX_EVIDENCE_CHARS) {
    const cut = out.slice(0, MAX_EVIDENCE_CHARS);
    const lastSpace = cut.lastIndexOf(" ");
    out = lastSpace > MAX_EVIDENCE_CHARS * 0.5 ? cut.slice(0, lastSpace) : cut;
    clipped = true;
  }
  return clipped ? out.trimEnd() + "…" : out;
}

// Re-validates a parsed model response against the rubric. Tolerant where
// safe (drop unknown flags/criteria, clamp scores, truncate strings) and
// strict where it matters (enums, required shape).
export function validateEvalResponse(
  parsed: unknown,
  rubric: Rubric
): EvalValidation {
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return {ok: false, reason: "not_an_object"};
  }
  const record = parsed as Record<string, unknown>;

  if (typeof record.summary !== "string" || !record.summary.trim()) {
    return {ok: false, reason: "missing_summary"};
  }
  if (
    typeof record.overallLevel !== "string" ||
    !OVERALL_LEVELS.includes(record.overallLevel)
  ) {
    return {ok: false, reason: "invalid_overall_level"};
  }
  if (
    typeof record.confidence !== "string" ||
    !CONFIDENCE_LEVELS.includes(record.confidence)
  ) {
    return {ok: false, reason: "invalid_confidence"};
  }
  if (typeof record.assessable !== "boolean") {
    return {ok: false, reason: "invalid_assessable"};
  }

  const knownCriteria = new Set(rubric.criteria.map((c) => c.id));
  const criterionScores: ValidatedCriterionScore[] = [];
  if (!Array.isArray(record.criterionScores)) {
    return {ok: false, reason: "invalid_criterion_scores"};
  }
  for (const entry of record.criterionScores) {
    if (!entry || typeof entry !== "object") continue;
    const item = entry as Record<string, unknown>;
    const criterionId =
      typeof item.criterionId === "string" ? item.criterionId : "";
    if (!knownCriteria.has(criterionId)) continue;
    if (criterionScores.some((c) => c.criterionId === criterionId)) continue;
    const rawScore = typeof item.score === "number" ? item.score : NaN;
    if (!Number.isFinite(rawScore)) continue;
    const score = Math.max(
      MIN_CRITERION_SCORE,
      Math.min(MAX_CRITERION_SCORE, Math.round(rawScore))
    );
    const evidence =
      typeof item.evidence === "string" ?
        clampEvidence(item.evidence.trim()) :
        "";
    criterionScores.push({criterionId, score, evidence});
  }
  if (record.assessable === true && criterionScores.length === 0) {
    return {ok: false, reason: "assessable_without_criteria"};
  }

  const flags: string[] = [];
  if (Array.isArray(record.flags)) {
    for (const flag of record.flags) {
      if (
        typeof flag === "string" &&
        MODEL_FLAGS.includes(flag) &&
        !flags.includes(flag)
      ) {
        flags.push(flag);
      }
    }
  }

  return {
    ok: true,
    value: {
      summary: truncate(record.summary.trim(), MAX_SUMMARY_CHARS),
      criterionScores,
      overallLevel: record.overallLevel,
      confidence: record.confidence,
      flags,
      assessable: record.assessable,
    },
  };
}

// Coarse internal ordering key ONLY (0–100). Never rendered in app,
// portal or CSV — UI shows overallLevel + confidence.
export function computeSortKey(value: ValidatedEvalResponse): number {
  if (!value.assessable || value.criterionScores.length === 0) return 0;
  const total = value.criterionScores.reduce((sum, c) => sum + c.score, 0);
  const max = value.criterionScores.length * MAX_CRITERION_SCORE;
  return Math.round((total / max) * 100);
}

export function validateClassificationResponse(
  parsed: unknown
): {ok: true, categories: string[]} | {ok: false} {
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return {ok: false};
  }
  const record = parsed as Record<string, unknown>;
  if (!Array.isArray(record.categories)) return {ok: false};
  const categories: string[] = [];
  for (const category of record.categories) {
    if (
      typeof category === "string" &&
      QUESTION_CATEGORIES.includes(category) &&
      !categories.includes(category)
    ) {
      categories.push(category);
    }
  }
  if (categories.length === 0) return {ok: false};
  return {ok: true, categories};
}
