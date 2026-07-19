// Versioned v1 rubrics for comprehension evaluation (Phase 3 — dark).
//
// Rubric contents ride PR review; every eval stamps rubricKey +
// rubricVersion + promptVersion so old evals stay interpretable. Scoring-
// material changes are allowed at term boundaries only, and report trends
// segment at version boundaries.

export const RUBRIC_VERSION = 1;

export const QUESTION_CATEGORIES: readonly string[] = [
  "literal_recall",
  "sequencing",
  "inference",
  "vocabulary",
  "personal_connection",
  "open_retell",
];

export interface RubricCriterion {
  id: string;
  label: string;
  guidance: string;
}

export interface Rubric {
  key: string;
  label: string;
  criteria: RubricCriterion[];
}

export const DEFAULT_RUBRIC_KEY = "general";

export const RUBRICS: Record<string, Rubric> = {
  literal_recall: {
    key: "literal_recall",
    label: "Literal recall",
    criteria: [
      {
        id: "recall",
        label: "Recalls events",
        guidance: "Accurately recalls at least one event or fact from the reading.",
      },
      {
        id: "sequence",
        label: "Orders events",
        guidance: "Retells events in a sensible order where order applies.",
      },
      {
        id: "detail",
        label: "Supporting detail",
        guidance: "Mentions a supporting detail (who, where, why or how).",
      },
    ],
  },
  inference: {
    key: "inference",
    label: "Inference",
    criteria: [
      {
        id: "inference",
        label: "Makes an inference",
        guidance: "Goes beyond the literal text to explain why or what might happen.",
      },
      {
        id: "text_support",
        label: "Supports from the text",
        guidance: "Connects the inference to something that happened in the reading.",
      },
      {
        id: "plausibility",
        label: "Plausibility",
        guidance: "The inference is reasonable for the story or topic.",
      },
    ],
  },
  vocabulary: {
    key: "vocabulary",
    label: "Vocabulary",
    criteria: [
      {
        id: "word_meaning",
        label: "Word meaning",
        guidance: "Shows understanding of the word or phrase in question.",
      },
      {
        id: "context_use",
        label: "Uses context",
        guidance: "Relates the meaning to how it was used in the reading.",
      },
      {
        id: "expression",
        label: "Expression",
        guidance: "Explains in their own words rather than repeating verbatim.",
      },
    ],
  },
  personal_connection: {
    key: "personal_connection",
    label: "Personal connection",
    criteria: [
      {
        id: "connection",
        label: "Makes a connection",
        guidance: "Relates the reading to their own life, feelings or experiences.",
      },
      {
        id: "relevance",
        label: "Relevance",
        guidance: "The connection clearly relates to the reading content.",
      },
      {
        id: "elaboration",
        label: "Elaboration",
        guidance: "Adds an explanation or example, not just a bare statement.",
      },
    ],
  },
  general: {
    key: "general",
    label: "General retell",
    criteria: [
      {
        id: "relevance",
        label: "Answers the question",
        guidance: "The response addresses the question that was asked.",
      },
      {
        id: "understanding",
        label: "Shows understanding",
        guidance: "Demonstrates understanding of what was read.",
      },
      {
        id: "expression",
        label: "Expresses ideas",
        guidance: "Communicates ideas in their own words, allowing for age and disfluency.",
      },
    ],
  },
};

// Maps question categories to the rubric used for scoring. Sequencing and
// open retell share the literal-recall/general shapes in v1.
const CATEGORY_TO_RUBRIC: Record<string, string> = {
  literal_recall: "literal_recall",
  sequencing: "literal_recall",
  inference: "inference",
  vocabulary: "vocabulary",
  personal_connection: "personal_connection",
  open_retell: "general",
};

export function rubricForKey(key: unknown): Rubric {
  if (typeof key === "string" && RUBRICS[key]) return RUBRICS[key];
  return RUBRICS[DEFAULT_RUBRIC_KEY];
}

export function rubricKeyForCategories(categories: unknown): string {
  if (Array.isArray(categories)) {
    for (const category of categories) {
      if (typeof category === "string" && CATEGORY_TO_RUBRIC[category]) {
        return CATEGORY_TO_RUBRIC[category];
      }
    }
  }
  return DEFAULT_RUBRIC_KEY;
}

export function isKnownCategory(category: unknown): boolean {
  return typeof category === "string" && QUESTION_CATEGORIES.includes(category);
}
