const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {errorCodeForLog} = require("../lib/log_safety");

test("errorCodeForLog preserves only bounded machine-readable codes", () => {
  assert.equal(errorCodeForLog({code: "auth/id-token-expired"}), "auth/id-token-expired");
  assert.equal(errorCodeForLog({status: 503}), "http_503");
  assert.equal(errorCodeForLog(new TypeError("child@example.com")), "TypeError");
});

test("errorCodeForLog rejects code strings that could contain personal data", () => {
  assert.equal(errorCodeForLog({code: "failed for child@example.com"}), "unknown");
  assert.equal(errorCodeForLog("child@example.com"), "unknown");
});

function sourceFiles(dir) {
  return fs.readdirSync(dir, {withFileTypes: true}).flatMap((entry) => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) return sourceFiles(full);
    return entry.isFile() && entry.name.endsWith(".ts") ? [full] : [];
  });
}

function loggerCallAt(text, openParen) {
  let depth = 1;
  let quote = null;
  let escaped = false;
  for (let i = openParen + 1; i < text.length; i++) {
    const char = text[i];
    if (quote !== null) {
      if (escaped) {
        escaped = false;
      } else if (char === "\\") {
        escaped = true;
      } else if (char === quote) {
        quote = null;
      }
      continue;
    }
    if (char === "\"" || char === "'" || char === "`") {
      quote = char;
    } else if (char === "(") {
      depth++;
    } else if (char === ")") {
      depth--;
      if (depth === 0) return text.slice(openParen, i + 1);
    }
  }
  return text.slice(openParen);
}

test("structured application logs do not include direct user or record identifiers", () => {
  const src = path.resolve(__dirname, "../src");
  const forbiddenField = /\b(?:school|student|parent|teacher|user|log|doc|book|session|parentEmail|email|phoneTail|schoolId|studentId|parentId|teacherId|userId|uid|logId|docId|bookId|sessionId|devUid|devEmail|targetSchoolId|targetUserId|emailHash|logPath|storagePath|objectName|objectPath)\s*[:,}]/;
  const identifierInterpolation = /\$\{[^}]*(?:school|student|parent|teacher|user|uid|email|phone|log|doc|book|session|target)/i;
  const identifierConcatenation = /\+\s*(?:school|student|parent|teacher|user|uid|email|phone|log|doc|book|session|target)\w*/i;
  const rawErrorPayload = /(?:,\s*(?:err|error)\s*\)$|\berror\s*:\s*(?!errorCodeForLog\s*\())/;
  const violations = [];

  for (const file of sourceFiles(src)) {
    const text = fs.readFileSync(file, "utf8");
    const loggerCall = /(?:functions\.)?logger\.(?:info|warn|error|debug)\s*\(/g;
    for (const match of text.matchAll(loggerCall)) {
      const openParen = match.index + match[0].lastIndexOf("(");
      const call = loggerCallAt(text, openParen);
      if (
        forbiddenField.test(call) ||
        identifierInterpolation.test(call) ||
        identifierConcatenation.test(call) ||
        rawErrorPayload.test(call)
      ) {
        const line = text.slice(0, match.index).split("\n").length;
        violations.push(`${path.relative(src, file)}:${line}`);
      }
    }
  }

  assert.deepEqual(violations, []);
});
