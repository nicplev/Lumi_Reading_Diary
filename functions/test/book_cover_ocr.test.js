// Pure-function tests for the book-cover OCR layer: kill-switch resolution,
// image budget, response re-validation and request-body shape.
const test = require("node:test");
const assert = require("node:assert/strict");

const {
  coverOcrEnabledFromDoc,
  assertCoverImageBudget,
  validateCoverOcrResponse,
  extractResponseText,
  buildCoverOcrRequestBody,
  COVER_OCR_SCHEMA,
  MAX_COVER_IMAGE_BYTES,
  MAX_TITLE_CHARS,
  MAX_AUTHOR_CHARS,
} = require("../lib/book_cover_ocr.js");

// ── Kill switch ─────────────────────────────────────────────────────────
// This gate fails OPEN, deliberately unlike ai_evaluation/gates.ts. If these
// invert, cover OCR silently stops working for every school with no signal.

test("kill switch: a missing doc leaves the feature enabled", () => {
  assert.equal(coverOcrEnabledFromDoc(undefined), true);
  assert.equal(coverOcrEnabledFromDoc(null), true);
});

test("kill switch: only a literal false closes the gate", () => {
  assert.equal(coverOcrEnabledFromDoc({enabled: false}), false);
  assert.equal(coverOcrEnabledFromDoc({enabled: true}), true);
  // Absent/garbage field must not disable a benign feature.
  assert.equal(coverOcrEnabledFromDoc({}), true);
  assert.equal(coverOcrEnabledFromDoc({enabled: "false"}), true);
  assert.equal(coverOcrEnabledFromDoc({enabled: 0}), true);
  assert.equal(coverOcrEnabledFromDoc("nonsense"), true);
  assert.equal(coverOcrEnabledFromDoc([]), true);
});

// ── Image budget ────────────────────────────────────────────────────────

test("image budget accepts a realistic downscaled cover", () => {
  assert.doesNotThrow(() => assertCoverImageBudget(180_000));
  assert.doesNotThrow(() => assertCoverImageBudget(MAX_COVER_IMAGE_BYTES));
});

test("image budget rejects empty and oversized payloads", () => {
  assert.throws(() => assertCoverImageBudget(0));
  assert.throws(() => assertCoverImageBudget(-1));
  assert.throws(() => assertCoverImageBudget(NaN));
  assert.throws(() => assertCoverImageBudget(MAX_COVER_IMAGE_BYTES + 1));
});

// ── Response re-validation ──────────────────────────────────────────────

test("validate accepts a well-formed response", () => {
  const out = validateCoverOcrResponse({
    title: "The Gruffalo",
    titleConfidence: 0.94,
    author: "Julia Donaldson",
    authorConfidence: 0.88,
  });
  assert.deepEqual(out, {
    title: "The Gruffalo",
    titleConfidence: 0.94,
    author: "Julia Donaldson",
    authorConfidence: 0.88,
  });
});

test("validate returns null for structurally unusable responses", () => {
  assert.equal(validateCoverOcrResponse(null), null);
  assert.equal(validateCoverOcrResponse("a string"), null);
  assert.equal(validateCoverOcrResponse([1, 2]), null);
});

test("validate degrades missing fields rather than rejecting the whole", () => {
  const out = validateCoverOcrResponse({title: "Zog", titleConfidence: 0.9});
  assert.equal(out.title, "Zog");
  assert.equal(out.titleConfidence, 0.9);
  assert.equal(out.author, "");
  assert.equal(out.authorConfidence, 0);
});

test("validate clamps out-of-range confidence", () => {
  const out = validateCoverOcrResponse({
    title: "A", titleConfidence: 5,
    author: "B", authorConfidence: -3,
  });
  assert.equal(out.titleConfidence, 1);
  assert.equal(out.authorConfidence, 0);
});

test("validate zeroes confidence for non-numeric scores", () => {
  const out = validateCoverOcrResponse({
    title: "A", titleConfidence: "high",
    author: "B", authorConfidence: NaN,
  });
  assert.equal(out.titleConfidence, 0);
  assert.equal(out.authorConfidence, 0);
});

test("an empty value can never carry confidence", () => {
  // Guards the auto-fill contract: a blank field with a high score would
  // otherwise clear a value the teacher had already typed.
  const out = validateCoverOcrResponse({
    title: "", titleConfidence: 0.99,
    author: "   ", authorConfidence: 0.99,
  });
  assert.equal(out.title, "");
  assert.equal(out.titleConfidence, 0);
  assert.equal(out.author, "");
  assert.equal(out.authorConfidence, 0);
});

test("validate collapses whitespace and truncates long fields", () => {
  const out = validateCoverOcrResponse({
    title: "  The   Very\nHungry  Caterpillar ",
    titleConfidence: 0.9,
    author: "x".repeat(MAX_AUTHOR_CHARS + 50),
    authorConfidence: 0.9,
  });
  assert.equal(out.title, "The Very Hungry Caterpillar");
  assert.equal(out.author.length, MAX_AUTHOR_CHARS);
});

test("validate truncates an overlong title", () => {
  const out = validateCoverOcrResponse({
    title: "t".repeat(MAX_TITLE_CHARS + 100),
    titleConfidence: 1,
    author: "",
    authorConfidence: 0,
  });
  assert.equal(out.title.length, MAX_TITLE_CHARS);
});

// ── Provider response extraction ────────────────────────────────────────

test("extractResponseText joins the candidate's text parts", () => {
  const text = extractResponseText({
    candidates: [{content: {parts: [{text: "{\"ti"}, {text: "tle\":\"Z\"}"}]}}],
  });
  assert.equal(text, "{\"title\":\"Z\"}");
});

test("extractResponseText yields empty for a blocked or empty response", () => {
  // A safety block arrives as promptFeedback with no candidates; the caller
  // turns "" into the empty suggestion, i.e. today's manual entry.
  assert.equal(extractResponseText({promptFeedback: {blockReason: "SAFETY"}}), "");
  assert.equal(extractResponseText({candidates: []}), "");
  assert.equal(extractResponseText({}), "");
  assert.equal(extractResponseText(null), "");
});

test("a non-JSON model body is caught by the caller's JSON.parse", () => {
  assert.throws(() => JSON.parse(extractResponseText({
    candidates: [{content: {parts: [{text: "I'm sorry, I can't help."}]}}],
  })));
});

// ── Request body ────────────────────────────────────────────────────────

test("request body sends the image as an inlineData JPEG part", () => {
  const body = buildCoverOcrRequestBody("QUJD");
  const parts = body.contents[0].parts;
  assert.equal(parts[0].inlineData.mimeType, "image/jpeg");
  assert.equal(parts[0].inlineData.data, "QUJD");
  assert.ok(typeof parts[1].text === "string" && parts[1].text.length > 0);
});

test("request body pins deterministic structured output", () => {
  const cfg = buildCoverOcrRequestBody("QUJD").generationConfig;
  assert.equal(cfg.temperature, 0);
  assert.equal(cfg.responseMimeType, "application/json");
  assert.equal(cfg.thinkingConfig.thinkingBudget, 0);
  assert.equal(cfg.responseSchema, COVER_OCR_SCHEMA);
});

test("schema requires both values and both confidences", () => {
  assert.deepEqual(
    COVER_OCR_SCHEMA.required,
    ["title", "titleConfidence", "author", "authorConfidence"]
  );
  // Each value decodes before its own confidence, so the score is produced
  // with the extracted text already in context.
  assert.ok(
    COVER_OCR_SCHEMA.propertyOrdering.indexOf("title") <
    COVER_OCR_SCHEMA.propertyOrdering.indexOf("titleConfidence")
  );
});
