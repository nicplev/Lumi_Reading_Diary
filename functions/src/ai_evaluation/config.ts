// Runtime configuration for the AI evaluation pipeline (Phase 3 — dark).
//
// Residency is a hard product guarantee: every provider call is pinned to
// australia-southeast1. The `global` location would silently break the
// all-Australian processing claim, so it is treated as a configuration
// error, not a fallback (docs/AI_EVALUATION_GEMINI_PLAN.md §3.2).

import * as admin from "firebase-admin";

export const AI_EVAL_REGION = "australia-southeast1";
export const AI_EVAL_VERTEX_BASE_URL =
  `https://${AI_EVAL_REGION}-aiplatform.googleapis.com`;
export const AI_EVAL_SPEECH_ENDPOINT = `${AI_EVAL_REGION}-speech.googleapis.com`;

// Code-reviewed allowlist of models with AU-regional probe evidence
// (docs/AI_EVALUATION_GEMINI_PLAN.md §12.2). Adding a model REQUIRES a new
// probe-evidence row in that document — an ops-config model outside this
// list defers jobs instead of silently routing elsewhere.
export const AI_EVAL_MODEL_ALLOWLIST: readonly string[] = ["gemini-2.5-flash"];
export const AI_EVAL_DEFAULT_MODEL = "gemini-2.5-flash";

// USD per 1M tokens, keyed by model. Used for estCostUsd metering and the
// sweep cost alarm; drift here shows up in metering, not in billing.
export const AI_EVAL_PRICE_TABLE: Record<
  string, {inputPerM: number, outputPerM: number}
> = {
  "gemini-2.5-flash": {inputPerM: 0.30, outputPerM: 2.50},
};

// Speech-to-Text V2 synchronous recognition, en-AU `long` model.
export const STT_PRICE_PER_BILLED_SEC_USD = 0.016 / 60;

// Throws when a provider call is about to leave the pinned region.
export function assertResidencyPinned(location: string): void {
  if (location !== AI_EVAL_REGION) {
    throw new Error(
      `AI evaluation residency violation: location "${location}" is not ` +
      `${AI_EVAL_REGION}. The global endpoint is never an allowed fallback.`
    );
  }
}

export function isAllowlistedModel(model: string): boolean {
  return AI_EVAL_MODEL_ALLOWLIST.includes(model);
}

export const AI_EVAL_OPS_CONFIG_DOC = "aiEvalOpsConfig/runtime";

export interface AiEvalOpsConfig {
  model: string;
  defaultDailyCapPerSchool: number;
  globalDailyCap: number;
  minDurationSec: number;
  maxTranscriptChars: number;
  evalTimeoutSec: number;
  maxAttempts: number;
  transcriptRetentionDays: number;
  evalRetentionDays: number;
  promptVersion: number;
  costAlarmDailyUsd: number;
}

export const AI_EVAL_OPS_DEFAULTS: AiEvalOpsConfig = {
  model: AI_EVAL_DEFAULT_MODEL,
  defaultDailyCapPerSchool: 200,
  globalDailyCap: 1000,
  minDurationSec: 4,
  maxTranscriptChars: 8000,
  evalTimeoutSec: 60,
  maxAttempts: 3,
  transcriptRetentionDays: 90,
  evalRetentionDays: 730,
  promptVersion: 1,
  costAlarmDailyUsd: 25,
};

function positiveNumber(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) && value > 0 ?
    value :
    fallback;
}

// Merges the deny-all ops doc over the defaults. Pure and tolerant: any
// malformed field falls back to its default.
export function mergeOpsConfig(data: unknown): AiEvalOpsConfig {
  const record =
    data && typeof data === "object" ? (data as Record<string, unknown>) : {};
  const d = AI_EVAL_OPS_DEFAULTS;
  return {
    model: typeof record.model === "string" && record.model.trim() ?
      record.model.trim() :
      d.model,
    defaultDailyCapPerSchool:
      positiveNumber(record.defaultDailyCapPerSchool, d.defaultDailyCapPerSchool),
    globalDailyCap: positiveNumber(record.globalDailyCap, d.globalDailyCap),
    minDurationSec: positiveNumber(record.minDurationSec, d.minDurationSec),
    maxTranscriptChars:
      positiveNumber(record.maxTranscriptChars, d.maxTranscriptChars),
    evalTimeoutSec: positiveNumber(record.evalTimeoutSec, d.evalTimeoutSec),
    maxAttempts: positiveNumber(record.maxAttempts, d.maxAttempts),
    transcriptRetentionDays:
      positiveNumber(record.transcriptRetentionDays, d.transcriptRetentionDays),
    evalRetentionDays:
      positiveNumber(record.evalRetentionDays, d.evalRetentionDays),
    promptVersion: positiveNumber(record.promptVersion, d.promptVersion),
    costAlarmDailyUsd:
      positiveNumber(record.costAlarmDailyUsd, d.costAlarmDailyUsd),
  };
}

const CONFIG_CACHE_TTL_MS = 60_000;
let cachedOpsConfig: AiEvalOpsConfig | null = null;
let cachedOpsConfigAt = 0;

export async function readAiEvalOpsConfig(): Promise<AiEvalOpsConfig> {
  const now = Date.now();
  if (cachedOpsConfig && now - cachedOpsConfigAt < CONFIG_CACHE_TTL_MS) {
    return cachedOpsConfig;
  }
  let data: unknown;
  try {
    const snap = await admin.firestore().doc(AI_EVAL_OPS_CONFIG_DOC).get();
    data = snap.exists ? snap.data() : undefined;
  } catch (err) {
    // Fail toward defaults: the defaults are conservative and the platform
    // kill switch (checked separately, fail-closed) still gates everything.
    data = undefined;
  }
  cachedOpsConfig = mergeOpsConfig(data);
  cachedOpsConfigAt = now;
  return cachedOpsConfig;
}

export function resetAiEvalConfigCacheForTest(): void {
  cachedOpsConfig = null;
  cachedOpsConfigAt = 0;
}

// USD cost estimate for one evaluation call under the pinned price table.
export function estimateEvalCostUsd(
  model: string,
  usage: {inputTokens: number, outputTokens: number, thoughtsTokens: number}
): number {
  const price = AI_EVAL_PRICE_TABLE[model];
  if (!price) return 0;
  const outputBilled = usage.outputTokens + usage.thoughtsTokens;
  return (
    (usage.inputTokens / 1_000_000) * price.inputPerM +
    (outputBilled / 1_000_000) * price.outputPerM
  );
}
