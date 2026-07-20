import test from "node:test";
import assert from "node:assert/strict";
import * as functionsGates from "../../../functions/src/ai_evaluation/gates";
import * as serverOpsAuthority from "../src/aiEvalAuthority";

test("Functions and server-ops use the same AI-eval authority contract", () => {
  assert.equal(
    serverOpsAuthority.AI_EVAL_AUTHORITY_VERSION,
    functionsGates.AI_EVAL_AUTHORITY_VERSION
  );

  const current = functionsGates.AI_EVAL_AUTHORITY_VERSION;
  const fixtures: unknown[] = [
    null,
    {},
    { settings: {} },
    // The switch alone is not entitlement.
    { settings: { aiEvaluation: { enabled: true } } },
    // What the pilot school actually held in prod before 2026-07-20: a
    // non-empty free-text string that proved nothing.
    {
      settings: {
        aiEvaluation: {
          enabled: true,
          termsVersionAccepted: "Terms version accepted",
        },
      },
    },
    // Superseded terms must fall out of entitlement.
    {
      settings: {
        aiEvaluation: {
          enabled: true,
          authorityVersion: "school-ai-eval-v0-2026-01-01",
          authorityConfirmedAt: new Date("2026-01-01T00:00:00Z"),
        },
      },
    },
    // Version without a confirmation stamp.
    {
      settings: {
        aiEvaluation: { enabled: true, authorityVersion: current },
      },
    },
    // Fully confirmed.
    {
      settings: {
        aiEvaluation: {
          enabled: true,
          authorityVersion: current,
          authorityConfirmedAt: new Date("2026-07-20T00:00:00Z"),
        },
      },
    },
    // Confirmed but switched off.
    {
      settings: {
        aiEvaluation: {
          enabled: false,
          authorityVersion: current,
          authorityConfirmedAt: new Date("2026-07-20T00:00:00Z"),
        },
      },
    },
  ];

  for (const school of fixtures) {
    assert.equal(
      serverOpsAuthority.schoolAiEvaluationEnabled(school),
      functionsGates.schoolAiEvaluationEnabled(school),
      JSON.stringify(school)
    );
  }

  for (const flag of [null, {}, { enabled: false }, { enabled: true }]) {
    assert.equal(
      serverOpsAuthority.platformAiEvaluationEnabled(flag),
      functionsGates.platformAiEvaluationEnabled(flag)
    );
  }
});

test("only the current version with a confirmation stamp opens the gate", () => {
  const current = serverOpsAuthority.AI_EVAL_AUTHORITY_VERSION;
  assert.equal(
    serverOpsAuthority.schoolAiEvaluationEnabled({
      settings: {
        aiEvaluation: {
          enabled: true,
          authorityVersion: current,
          authorityConfirmedAt: new Date(),
        },
      },
    }),
    true
  );
  assert.equal(
    serverOpsAuthority.schoolAiEvaluationEnabled({
      settings: { aiEvaluation: { enabled: true, authorityVersion: current } },
    }),
    false
  );
});
