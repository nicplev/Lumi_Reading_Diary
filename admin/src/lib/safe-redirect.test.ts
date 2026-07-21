import assert from "node:assert/strict";
import test from "node:test";
import { safeRedirectTarget } from "./safe-redirect.ts";

test("safeRedirectTarget preserves an internal dashboard deep link", () => {
  assert.equal(
    safeRedirectTarget("/feedback?status=new&item=abc#detail"),
    "/feedback?status=new&item=abc#detail"
  );
});

test("safeRedirectTarget rejects external and executable targets", () => {
  for (const target of [
    "https://attacker.example",
    "//attacker.example/path",
    "javascript:alert(1)",
    "/\\attacker.example",
    "/login?redirect=/feedback",
  ]) {
    assert.equal(safeRedirectTarget(target), "/");
  }
});
