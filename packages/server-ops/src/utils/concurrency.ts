/**
 * Run fn over items with a fixed concurrency, collecting settled results.
 *
 * Mirrors the private mapSettled in manageParentAccount.ts, lifted here for
 * fan-outs that must not spike memory. The portals run on a 512MiB
 * frameworksBackend, so an unbounded Promise.all over "every school" can
 * exhaust the container before it ever reaches a request timeout.
 */
export async function mapSettledWithLimit<T, R>(
  items: T[],
  limit: number,
  fn: (item: T) => Promise<R>
): Promise<PromiseSettledResult<R>[]> {
  const results = new Array<PromiseSettledResult<R>>(items.length);
  let cursor = 0;
  async function worker(): Promise<void> {
    while (cursor < items.length) {
      const i = cursor++;
      try {
        results[i] = { status: "fulfilled", value: await fn(items[i]) };
      } catch (reason) {
        results[i] = { status: "rejected", reason };
      }
    }
  }
  await Promise.all(
    Array.from({ length: Math.max(1, Math.min(limit, items.length)) }, () =>
      worker()
    )
  );
  return results;
}
