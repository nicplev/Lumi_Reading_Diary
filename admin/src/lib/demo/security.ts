import "server-only";
import { createHash } from "node:crypto";
import { getAdminDb } from "@/lib/firebase-admin";

export class DemoRouteSecurityError extends Error {
  status: number;
  constructor(message: string, status: number) {
    super(message);
    this.name = "DemoRouteSecurityError";
    this.status = status;
  }
}

export function assertSameOrigin(request: Request): void {
  const origin = request.headers.get("origin");
  const fetchSite = request.headers.get("sec-fetch-site");
  const forwardedHost = request.headers.get("x-forwarded-host")?.split(",")[0]?.trim();
  const expectedHost = forwardedHost || request.headers.get("host") || new URL(request.url).host;
  const forwardedProtocol = request.headers.get("x-forwarded-proto")?.split(",")[0]?.trim();
  const expectedProtocol = `${forwardedProtocol || new URL(request.url).protocol.replace(":", "")}:`;

  if (!origin) {
    throw new DemoRouteSecurityError("Missing request origin.", 403);
  }
  let parsedOrigin: URL;
  try {
    parsedOrigin = new URL(origin);
  } catch {
    throw new DemoRouteSecurityError("Invalid request origin.", 403);
  }
  if (
    parsedOrigin.host !== expectedHost ||
    parsedOrigin.protocol !== expectedProtocol ||
    (fetchSite && fetchSite !== "same-origin")
  ) {
    throw new DemoRouteSecurityError("Cross-origin request refused.", 403);
  }
}

interface Limit {
  key: string;
  max: number;
  windowMs: number;
}

/** Fixed-window, Firestore-backed limits survive instances and restarts. */
export async function consumeDemoRouteLimits(limits: Limit[]): Promise<void> {
  const db = getAdminDb();
  const now = new Date();
  await db.runTransaction(async (tx) => {
    // Firestore transactions require every read before the first write.
    const entries = limits.map((limit) => ({
      limit,
      ref: db.collection("adminRateLimits").doc(
        `demo_${createHash("sha256").update(limit.key).digest("hex")}`
      ),
    }));
    const snapshots = await tx.getAll(...entries.map((entry) => entry.ref));
    for (const [index, entry] of entries.entries()) {
      const { limit, ref } = entry;
      const snap = snapshots[index];
      const data = snap.data();
      const resetAt = data?.resetAt?.toDate?.() as Date | undefined;
      const withinWindow = resetAt instanceof Date && resetAt > now;
      const count = withinWindow && typeof data?.count === "number" ? data.count : 0;
      if (count >= limit.max) {
        throw new DemoRouteSecurityError(
          "Too many demo operations. Wait for the current limit window to reset.",
          429
        );
      }
      tx.set(ref, {
        count: count + 1,
        resetAt: withinWindow ? resetAt : new Date(now.getTime() + limit.windowMs),
        updatedAt: now,
      });
    }
  });
}
