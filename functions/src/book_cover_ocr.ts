// Book-cover OCR — auto-fills title/author when a teacher contributes a NEW
// book to the global `community_books` catalog.
//
// This runs only after `lookupByIsbn`'s five-tier chain has already missed,
// i.e. no catalog anywhere knows the ISBN and the teacher would otherwise be
// typing both fields by hand next to a photo of the cover.
//
// SCOPE NOTE: the payload is a book cover and the result is catalog metadata.
// No student data is involved, which is why this is gated by a single
// platform kill switch rather than the fail-CLOSED per-school entitlement in
// ai_evaluation/gates.ts — a school that has not signed the AI-evaluation
// authority (which is about student voice recordings) should still get this.

import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {assertNotReadOnly} from "./read_only_guard";
import {errorCodeForLog} from "./log_safety";
import {AI_EVAL_DEFAULT_MODEL} from "./ai_evaluation/config";
import {vertexGenerateContent} from "./ai_evaluation/vertex_rest";

export const COVER_OCR_FLAG_DOC = "platformConfig/coverOcr";

const COVER_OCR_TIMEOUT_MS = 30_000;
const COVER_OCR_APP_CHECK_ENFORCED =
  process.env.COVER_OCR_APP_CHECK_ENFORCED === "true";

// Decoded-image ceiling. A ~1024px cover at q80 lands around 100-200 KB, so
// this is generous headroom rather than a working constraint.
//
// RESIDENCY: assertResidencyPromptBudget (ai_evaluation/evaluation.ts) counts
// only STRING lengths, so an image part slips past it while still consuming
// context tokens. A cover is ~1-2k tokens against the 128k tier that carries
// the Australian ML-processing commitment (ai_evaluation/config.ts), so we are
// nowhere near it — but the invariant has to stay auditable, hence this bound.
export const MAX_COVER_IMAGE_BYTES = 1_048_576;

// base64 inflates by 4/3; reject on the encoded string before spending memory
// decoding a payload we are going to refuse anyway.
const MAX_COVER_IMAGE_B64_CHARS = Math.ceil(MAX_COVER_IMAGE_BYTES * 4 / 3) + 8;

export const MAX_TITLE_CHARS = 300;
export const MAX_AUTHOR_CHARS = 200;

// ── Kill switch ─────────────────────────────────────────────────────────
// Resolution table, deliberately NOT the gates.ts fail-closed model:
//
//   missing doc       -> ENABLED   (platformConfig house convention; shipping
//                                   needs no seeding step)
//   {enabled: false}  -> DISABLED
//   read error        -> ENABLED   (a benign metadata feature must not break
//                                   because of an unrelated Firestore blip)
//
// Only the literal `false` closes the gate. Flipping it in the console takes
// effect fleet-wide within the cache TTL, with no deploy — which matters
// because Cloud Functions in this repo are not CI-deployed.
export function coverOcrEnabledFromDoc(data: unknown): boolean {
  if (!data || typeof data !== "object" || Array.isArray(data)) return true;
  return (data as Record<string, unknown>).enabled !== false;
}

const FLAG_CACHE_TTL_MS = 60_000;
let cachedFlag: boolean | null = null;
let cachedFlagAt = 0;

export async function readCoverOcrEnabled(): Promise<boolean> {
  const now = Date.now();
  if (cachedFlag !== null && now - cachedFlagAt < FLAG_CACHE_TTL_MS) {
    return cachedFlag;
  }
  let enabled = true;
  try {
    const snap = await admin.firestore().doc(COVER_OCR_FLAG_DOC).get();
    enabled = coverOcrEnabledFromDoc(snap.exists ? snap.data() : undefined);
  } catch (err: unknown) {
    functions.logger.warn("coverOcr.flagReadFailed", {
      errorCode: errorCodeForLog(err),
    });
    enabled = true;
  }
  cachedFlag = enabled;
  cachedFlagAt = now;
  return enabled;
}

// ── Request budget ──────────────────────────────────────────────────────

export function assertCoverImageBudget(byteLength: number): void {
  if (!Number.isFinite(byteLength) || byteLength <= 0) {
    throw new HttpsError("invalid-argument", "Cover image is empty.");
  }
  if (byteLength > MAX_COVER_IMAGE_BYTES) {
    throw new HttpsError("invalid-argument", "Cover image is too large.");
  }
}

// ── Model contract ──────────────────────────────────────────────────────

// Vertex structured-output schema (OpenAPI subset, uppercase types).
// propertyOrdering decodes each value before its confidence, so the score is
// produced with the extracted text already in context — ordering-as-reasoning.
export const COVER_OCR_SCHEMA = {
  type: "OBJECT",
  properties: {
    title: {type: "STRING"},
    titleConfidence: {type: "NUMBER"},
    author: {type: "STRING"},
    authorConfidence: {type: "NUMBER"},
  },
  required: ["title", "titleConfidence", "author", "authorConfidence"],
  propertyOrdering: [
    "title", "titleConfidence", "author", "authorConfidence",
  ],
};

// The whole reason for using a vision model over plain OCR is this prompt:
// raw text recognition returns lines and boxes, and "biggest line wins" gets
// the award sticker or the series name on a large share of children's covers.
export const COVER_OCR_PROMPT = [
  "You are reading the FRONT COVER of a children's or primary-school book.",
  "Return the book's title and the author's name as printed on the cover.",
  "",
  "TITLE rules:",
  "- The title is the book's own title. It is NOT the series name, NOT a",
  "  subtitle or tagline, NOT an award or marketing sticker (\"WINNER\",",
  "  \"BESTSELLER\", \"NOW A MAJOR FILM\"), and NOT the publisher or imprint.",
  "- The title is often, but NOT always, the largest text on the cover.",
  "- If both a series name and a title appear, return only the title.",
  "",
  "AUTHOR rules:",
  "- The author is the writer. Where the cover credits an illustrator",
  "  separately (\"illustrated by\", \"pictures by\"), return the WRITER only.",
  "- Drop a leading \"by\".",
  "",
  "Formatting:",
  "- Convert ALL-CAPS display text to Title Case; otherwise keep the",
  "  printed capitalisation.",
  "",
  "If you cannot read a field, return an empty string and 0 confidence for",
  "it. NEVER guess, and never invent a plausible title or author.",
  "",
  "Confidence is 0..1: how sure you are that the value is correct AND is the",
  "thing asked for, rather than a series name, publisher or illustrator.",
].join("\n");

export interface ValidatedCoverOcr {
  title: string;
  titleConfidence: number;
  author: string;
  authorConfidence: number;
}

// Frozen because it is returned by reference from every failure path; an
// in-place mutation anywhere would poison responses for the whole instance.
export const EMPTY_COVER_OCR: ValidatedCoverOcr = Object.freeze({
  title: "",
  titleConfidence: 0,
  author: "",
  authorConfidence: 0,
});

function cleanField(value: unknown, maxChars: number): string {
  if (typeof value !== "string") return "";
  return value.trim().replace(/\s+/g, " ").slice(0, maxChars);
}

// Confidence is advisory, so a malformed score degrades that field to 0
// (which the client reads as "do not auto-fill") instead of discarding an
// otherwise good response.
function cleanConfidence(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return 0;
  return Math.max(0, Math.min(1, value));
}

// Re-validates the parsed model response. The Vertex responseSchema
// constrains decoding, but per the house rule in ai_evaluation/schemas.ts
// constrained decoding is never trusted as validation.
//
// Returns null only for structurally unusable responses; anything salvageable
// degrades to empty-string/0-confidence fields.
export function validateCoverOcrResponse(
  parsed: unknown
): ValidatedCoverOcr | null {
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return null;
  }
  const record = parsed as Record<string, unknown>;
  const title = cleanField(record.title, MAX_TITLE_CHARS);
  const author = cleanField(record.author, MAX_AUTHOR_CHARS);
  return {
    title,
    // An empty value can never carry confidence, whatever the model claimed.
    titleConfidence: title ? cleanConfidence(record.titleConfidence) : 0,
    author,
    authorConfidence: author ? cleanConfidence(record.authorConfidence) : 0,
  };
}

// Pulls the concatenated text parts out of a generateContent response.
// A safety block or empty candidate list yields "" and therefore a null
// validation, which the caller turns into the empty (no-suggestion) result.
export function extractResponseText(response: unknown): string {
  if (!response || typeof response !== "object") return "";
  const candidates = (response as {
    candidates?: Array<{content?: {parts?: Array<{text?: string}>}}>,
  }).candidates;
  if (!Array.isArray(candidates) || candidates.length === 0) return "";
  return candidates[0]?.content?.parts?.map((p) => p.text ?? "").join("") ?? "";
}

export function buildCoverOcrRequestBody(
  imageBase64: string
): Record<string, unknown> {
  return {
    contents: [{
      role: "user",
      parts: [
        {inlineData: {mimeType: "image/jpeg", data: imageBase64}},
        {text: COVER_OCR_PROMPT},
      ],
    }],
    generationConfig: {
      temperature: 0,
      maxOutputTokens: 300,
      responseMimeType: "application/json",
      responseSchema: COVER_OCR_SCHEMA,
      thinkingConfig: {thinkingBudget: 0},
    },
  };
}

// ── Callable ────────────────────────────────────────────────────────────

const COVER_OCR_CALLABLE_OPTIONS = {
  timeoutSeconds: 60,
  memory: "512MiB" as const,
  maxInstances: 10,
  enforceAppCheck: COVER_OCR_APP_CHECK_ENFORCED,
  consumeAppCheckToken: COVER_OCR_APP_CHECK_ENFORCED,
};

// Reads a book cover and returns suggested catalog metadata.
//
// Every failure path returns EMPTY_COVER_OCR rather than throwing, so the
// client's silent-degrade path lands on exactly today's manual-entry
// behaviour. Only caller errors (unauthenticated, not a teacher, oversized
// image) throw — those are bugs, not conditions to paper over.
export const extractBookCoverMetadata = onCall(
  COVER_OCR_CALLABLE_OPTIONS,
  async (request) => {
    assertNotReadOnly(request);
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

    // Kill switch before any Vertex call. Checked after the (I/O-free) auth
    // guard above so an unauthenticated caller cannot probe the flag state.
    if (!await readCoverOcrEnabled()) {
      return {...EMPTY_COVER_OCR, disabled: true};
    }

    const data = request.data ?? {};
    const schoolId =
      typeof data.schoolId === "string" ? data.schoolId.trim() : "";
    const imageBase64 =
      typeof data.imageBase64 === "string" ? data.imageBase64 : "";
    if (!schoolId || !imageBase64) {
      throw new HttpsError(
        "invalid-argument", "schoolId and imageBase64 are required"
      );
    }
    if (imageBase64.length > MAX_COVER_IMAGE_B64_CHARS) {
      throw new HttpsError("invalid-argument", "Cover image is too large.");
    }
    assertCoverImageBudget(Buffer.from(imageBase64, "base64").length);

    // Mirrors what firestore.rules demands for a community_books create:
    // only a teacher or admin OF THE DECLARED SCHOOL may contribute.
    const userSnap = await admin.firestore()
      .doc(`schools/${schoolId}/users/${uid}`).get();
    const role = userSnap.data()?.role;
    if (role !== "teacher" && role !== "schoolAdmin") {
      throw new HttpsError(
        "permission-denied", "Only teachers can add books to the catalog"
      );
    }

    try {
      const response = await vertexGenerateContent(
        AI_EVAL_DEFAULT_MODEL,
        buildCoverOcrRequestBody(imageBase64),
        COVER_OCR_TIMEOUT_MS
      );
      const text = extractResponseText(response);
      if (!text) return EMPTY_COVER_OCR;
      const validated = validateCoverOcrResponse(JSON.parse(text));
      if (!validated) return EMPTY_COVER_OCR;
      // Report the model back rather than letting the client hardcode it,
      // so stored provenance can never drift from what actually ran.
      return {...validated, model: AI_EVAL_DEFAULT_MODEL};
    } catch (err: unknown) {
      // Provider outage, timeout, safety block or malformed JSON — the
      // teacher types the details, exactly as they do today.
      functions.logger.warn("coverOcr.callFailed", {
        errorCode: errorCodeForLog(err),
      });
      return EMPTY_COVER_OCR;
    }
  }
);
