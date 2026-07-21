import test from "node:test";
import assert from "node:assert/strict";
import { mapSettledWithLimit } from "../src/utils/concurrency";

test("never exceeds the concurrency limit", async () => {
  let inFlight = 0;
  let peak = 0;
  const items = Array.from({ length: 50 }, (_, i) => i);

  await mapSettledWithLimit(items, 5, async (i) => {
    inFlight++;
    peak = Math.max(peak, inFlight);
    await new Promise((resolve) => setTimeout(resolve, i % 3));
    inFlight--;
    return i;
  });

  assert.ok(peak <= 5, `peak concurrency was ${peak}, expected <= 5`);
  assert.ok(peak > 1, "expected some overlap, got fully serial execution");
});

test("processes every item exactly once and preserves order", async () => {
  const items = ["a", "b", "c", "d", "e"];
  const seen: string[] = [];

  const results = await mapSettledWithLimit(items, 2, async (item) => {
    seen.push(item);
    return item.toUpperCase();
  });

  assert.equal(seen.length, items.length);
  assert.deepEqual([...seen].sort(), [...items].sort());
  assert.deepEqual(
    results.map((r) => (r.status === "fulfilled" ? r.value : null)),
    ["A", "B", "C", "D", "E"]
  );
});

test("one rejection does not sink the rest", async () => {
  const results = await mapSettledWithLimit([1, 2, 3, 4], 2, async (n) => {
    if (n === 2) throw new Error("boom");
    return n * 10;
  });

  assert.equal(results[1].status, "rejected");
  assert.equal(
    (results[1] as PromiseRejectedResult).reason.message,
    "boom"
  );
  // The remaining items still completed.
  assert.deepEqual(
    results
      .filter((r) => r.status === "fulfilled")
      .map((r) => (r as PromiseFulfilledResult<number>).value),
    [10, 30, 40]
  );
});

test("handles an empty list and a limit above the item count", async () => {
  assert.deepEqual(await mapSettledWithLimit([], 5, async () => 1), []);

  const results = await mapSettledWithLimit([1, 2], 99, async (n) => n);
  assert.equal(results.length, 2);
  assert.equal(results[0].status, "fulfilled");
});

test("a limit of zero still makes progress rather than deadlocking", async () => {
  const results = await mapSettledWithLimit([1, 2, 3], 0, async (n) => n);
  assert.equal(results.length, 3);
  assert.ok(results.every((r) => r.status === "fulfilled"));
});
