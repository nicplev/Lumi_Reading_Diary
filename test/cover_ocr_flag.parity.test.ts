import test from "node:test";
import assert from "node:assert/strict";
import * as functionsOcr from "../functions/src/book_cover_ocr_flag";
import * as serverOpsOcr from "../packages/server-ops/src/coverOcr";

test("portal and callable resolve the cover-OCR flag identically", () => {
  const fixtures: unknown[] = [
    undefined,
    null,
    {},
    { enabled: true },
    { enabled: false },
    { enabled: "false" },
    { enabled: 0 },
    { enabled: null },
    { enabled: undefined },
    { somethingElse: true },
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

test("the cover-OCR flag fails open", () => {
  assert.equal(serverOpsOcr.coverOcrEnabledFromDoc(undefined), true);
  assert.equal(serverOpsOcr.coverOcrEnabledFromDoc({}), true);
  assert.equal(serverOpsOcr.coverOcrEnabledFromDoc({ enabled: false }), false);
});
