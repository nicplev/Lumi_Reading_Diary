// Sharded ops metrics + per-school monthly metering (Phase 3 — dark).
//
// Daily pipeline counters are sharded (10×, random write / sum on read)
// under deny-all aiEvalOpsConfig. Per-school monthly usage lives at
// schools/{s}/meta/aiEvalUsage keyed by "YYYY-MM" — it powers invoice
// reconciliation and the super-admin margin readout, and meters the
// classification and (Phase 7) narrative calls too.

import * as functions from "firebase-functions/v1";
import {FieldValue} from "firebase-admin/firestore";
import {errorCodeForLog} from "../log_safety";
import {utcDayKey} from "./budget";

export const METRICS_SHARDS = 10;

export function metricsShardDocPath(day: string, shard: number): string {
  return `aiEvalOpsConfig/metrics_${day}_shard${shard}`;
}

export interface AiEvalMetricDeltas {
  evaluated?: number;
  flagged?: number;
  failed?: number;
  deferred?: number;
  poisoned?: number;
  safetyBlocks?: number;
  sttSeconds?: number;
  inputTokens?: number;
  outputTokens?: number;
  thoughtsTokens?: number;
  cachedTokens?: number;
  llmCalls?: number;
  classificationCalls?: number;
  estCostUsdMillis?: number;
}

// Fire-and-forget sharded daily counter increment.
export async function incrementDailyMetrics(
  db: FirebaseFirestore.Firestore,
  deltas: AiEvalMetricDeltas,
  now: Date,
  pickShard: () => number = () => Math.floor(Math.random() * METRICS_SHARDS)
): Promise<void> {
  const day = utcDayKey(now);
  const shard = Math.min(METRICS_SHARDS - 1, Math.max(0, pickShard()));
  const update: Record<string, unknown> = {date: day};
  for (const [key, value] of Object.entries(deltas)) {
    if (typeof value === "number" && value !== 0) {
      update[key] = FieldValue.increment(value);
    }
  }
  try {
    await db.doc(metricsShardDocPath(day, shard)).set(update, {merge: true});
  } catch (err: unknown) {
    functions.logger.warn("aiEval.metrics.incrementFailed", {
      errorCode: errorCodeForLog(err),
    });
  }
}

// Sums today's sharded counters (sweep cost alarm + observability).
export async function readDailyMetrics(
  db: FirebaseFirestore.Firestore,
  now: Date
): Promise<Record<string, number>> {
  const day = utcDayKey(now);
  const totals: Record<string, number> = {};
  for (let shard = 0; shard < METRICS_SHARDS; shard++) {
    const snap = await db.doc(metricsShardDocPath(day, shard)).get();
    const data = snap.data() ?? {};
    if (data.date !== day) continue;
    for (const [key, value] of Object.entries(data)) {
      if (key === "date" || typeof value !== "number") continue;
      totals[key] = (totals[key] ?? 0) + value;
    }
  }
  return totals;
}

export function monthKey(now: Date): string {
  return now.toISOString().slice(0, 7);
}

export interface SchoolUsageDeltas {
  evaluated?: number;
  sttSeconds?: number;
  inputTokens?: number;
  outputTokens?: number;
  thoughtsTokens?: number;
  cachedTokens?: number;
  classificationCalls?: number;
  narrativeCalls?: number;
  estCostUsdMillis?: number;
}

// Per-school monthly metering merge-increment.
export async function recordSchoolMonthlyUsage(
  db: FirebaseFirestore.Firestore,
  schoolId: string,
  deltas: SchoolUsageDeltas,
  now: Date
): Promise<void> {
  const month = monthKey(now);
  const update: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(deltas)) {
    if (typeof value === "number" && value !== 0) {
      update[`${month}.${key}`] = FieldValue.increment(value);
    }
  }
  if (Object.keys(update).length === 0) return;
  update.updatedAt = FieldValue.serverTimestamp();
  try {
    await db
      .doc(`schools/${schoolId}/meta/aiEvalUsage`)
      .set(expandDotted(update), {merge: true});
  } catch (err: unknown) {
    functions.logger.warn("aiEval.metrics.usageFailed", {
      errorCode: errorCodeForLog(err),
    });
  }
}

// set(..., {merge:true}) treats dots in keys literally, so expand
// "YYYY-MM.field" into nested maps before writing.
export function expandDotted(
  update: Record<string, unknown>
): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(update)) {
    const dot = key.indexOf(".");
    if (dot === -1) {
      out[key] = value;
      continue;
    }
    const head = key.slice(0, dot);
    const rest = key.slice(dot + 1);
    const existing = (out[head] ?? {}) as Record<string, unknown>;
    existing[rest] = value;
    out[head] = existing;
  }
  return out;
}
