// Daily spend caps (Phase 3 — dark).
//
// Two layers, both app-level HARD stops (GCP billing budgets only alert):
//  - per-school daily cap: schools/{s}/meta/aiEvalBudget, provisioned via
//    deny-all adminMeta capPerDay, defaulting from ops config.
//  - global daily cap: 10 sharded counters under aiEvalOpsConfig (deny-all)
//    — a single doc would melt at fleet maxInstances (plan challenge #4).
// Denials become `deferred` jobs the sweep retries after the date rolls.

import {FieldValue} from "firebase-admin/firestore";

export const GLOBAL_BUDGET_SHARDS = 10;

// UTC day key, matching the notificationBudget house pattern.
export function utcDayKey(now: Date): string {
  return now.toISOString().slice(0, 10);
}

export function globalShardDocPath(day: string, shard: number): string {
  return `aiEvalOpsConfig/globalBudget_${day}_shard${shard}`;
}

// Reads the provisioned per-school cap from deny-all adminMeta; malformed
// or missing values fall back to the ops default.
export function schoolCapFromAdminMeta(
  data: unknown,
  fallback: number
): number {
  const record =
    data && typeof data === "object" ? (data as Record<string, unknown>) : {};
  const cap = record.capPerDay;
  return typeof cap === "number" && Number.isFinite(cap) && cap >= 0 ?
    Math.floor(cap) :
    fallback;
}

// Transactional per-school daily reservation (reserveDailyRecipientBudget
// pattern). Returns false when the cap is exhausted.
export async function reserveSchoolDailyEvalBudget(
  db: FirebaseFirestore.Firestore,
  schoolId: string,
  cap: number,
  now: Date
): Promise<boolean> {
  const budgetRef = db.doc(`schools/${schoolId}/meta/aiEvalBudget`);
  const today = utcDayKey(now);
  return db.runTransaction(async (transaction) => {
    const snap = await transaction.get(budgetRef);
    const data = snap.data() ?? {};
    const used = data.date === today ? Number(data.count ?? 0) : 0;
    if (used + 1 > cap) return false;
    transaction.set(budgetRef, {
      date: today,
      count: used + 1,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
}

// Sharded global daily reservation: sums all shards inside the
// transaction, then increments one random shard when under the cap.
export async function reserveGlobalDailyEvalBudget(
  db: FirebaseFirestore.Firestore,
  cap: number,
  now: Date,
  pickShard: () => number = () => Math.floor(Math.random() * GLOBAL_BUDGET_SHARDS)
): Promise<boolean> {
  const today = utcDayKey(now);
  const refs: FirebaseFirestore.DocumentReference[] = [];
  for (let shard = 0; shard < GLOBAL_BUDGET_SHARDS; shard++) {
    refs.push(db.doc(globalShardDocPath(today, shard)));
  }
  const chosen = Math.min(
    GLOBAL_BUDGET_SHARDS - 1,
    Math.max(0, pickShard())
  );
  return db.runTransaction(async (transaction) => {
    let total = 0;
    const snaps = await Promise.all(refs.map((ref) => transaction.get(ref)));
    for (const snap of snaps) {
      const data = snap.data() ?? {};
      if (data.date === today) total += Number(data.count ?? 0);
    }
    if (total + 1 > cap) return false;
    const target = refs[chosen];
    const targetData = snaps[chosen].data() ?? {};
    const current = targetData.date === today ? Number(targetData.count ?? 0) : 0;
    transaction.set(target, {
      date: today,
      count: current + 1,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
}

// Sums today's global shard counters (sweep observability).
export async function readGlobalDailyEvalCount(
  db: FirebaseFirestore.Firestore,
  now: Date
): Promise<number> {
  const today = utcDayKey(now);
  let total = 0;
  for (let shard = 0; shard < GLOBAL_BUDGET_SHARDS; shard++) {
    const snap = await db.doc(globalShardDocPath(today, shard)).get();
    const data = snap.data() ?? {};
    if (data.date === today) total += Number(data.count ?? 0);
  }
  return total;
}
