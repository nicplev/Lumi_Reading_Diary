import test from "node:test";
import assert from "node:assert/strict";
import * as functionsOcr from "../../../functions/src/book_cover_ocr";
import * as serverOpsOcr from "../src/coverOcr";

// The super-admin card renders whatever the portal resolves, but the feature
// is actually gated by what the CALLABLE resolves. If the two ever disagreed,
// the switch would display a state the feature is not in — the worst failure
// mode for a kill switch, because it is silent and only discovered in an
// incident. These run both implementations over the same fixtures.

test("portal and callable resolve the cover-OCR flag identically", () => {
  const fixtures: unknown[] = [
    // The case that matters most: no document has ever been written.
    undefined,
    null,
    {},
    { enabled: true },
    { enabled: false },
    // Only a literal false may disable. Everything else is on.
    { enabled: "false" },
    { enabled: 0 },
    { enabled: null },
    { enabled: undefined },
    { somethingElse: true },
    // Hostile / malformed shapes.
    [],
    "nonsense",
    42,
    { enabled: { nested: false } },
  ];

  for (const fixture of fixtures) {
    assert.equal(
      serverOpsOcr.coverOcrEnabledFromDoc(fixture),
      functionsOcr.coverOcrEnabledFromDoc(fixture),
      `disagreement on ${JSON.stringify(fixture) ?? "undefined"}`
    );
  }
});

test("the flag fails OPEN — the opposite of the AI-evaluation gate", () => {
  // Deliberate asymmetry with gates.ts. A cover carries no student data, so
  // an unrelated Firestore outage must not disable catalog metadata help.
  assert.equal(serverOpsOcr.coverOcrEnabledFromDoc(undefined), true);
  assert.equal(serverOpsOcr.coverOcrEnabledFromDoc({}), true);
  assert.equal(serverOpsOcr.coverOcrEnabledFromDoc({ enabled: false }), false);
});
