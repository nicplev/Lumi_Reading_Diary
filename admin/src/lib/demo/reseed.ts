import "server-only";
import {
  demoSchoolConstants,
  reseedDemoSchool,
  type DemoReseedTrigger,
  type DemoReseedResult,
} from "@lumi/server-ops";
import { getAdminAuth, getAdminDb, getAdminStorage } from "@/lib/firebase-admin";
import { readDemoAccessConfig } from "@/lib/firestore/demo-access";

export async function runDemoReseed(
  actor: { uid: string; email?: string },
  trigger: DemoReseedTrigger
): Promise<DemoReseedResult> {
  const db = getAdminDb();
  const config = await readDemoAccessConfig();
  if (
    config.schoolId !== demoSchoolConstants.schoolId ||
    config.schoolId !== "lumi_demo_primary_school"
  ) {
    throw new Error("Safety stop: configured demo tenant does not match the immutable reseed target.");
  }
  const school = await db.collection("schools").doc(config.schoolId).get();
  if (!school.exists || school.data()?.isDemo !== true) {
    throw new Error("Safety stop: configured tenant is not authoritatively marked as demo data.");
  }
  return reseedDemoSchool(
    getAdminAuth(),
    db,
    getAdminStorage(),
    actor,
    { trigger }
  );
}
export async function getSanitisedDemoReseedStatus(): Promise<Record<string, unknown>> {
  const snap = await getAdminDb().doc("demoAccess/reseedStatus").get();
  if (!snap.exists) return { state: "never" };
  const data = snap.data() ?? {};
  const iso = (value: unknown): string | null =>
    value && typeof value === "object" && "toDate" in value &&
    typeof (value as { toDate?: unknown }).toDate === "function"
      ? (value as { toDate: () => Date }).toDate().toISOString()
      : null;
  return {
    state: typeof data.state === "string" ? data.state : "unknown",
    phase: typeof data.phase === "string" ? data.phase : null,
    trigger: typeof data.trigger === "string" ? data.trigger : null,
    startedAtISO: iso(data.startedAt),
    finishedAtISO: iso(data.finishedAt),
    docsWritten: typeof data.docsWritten === "number" ? data.docsWritten : 0,
    communityBooksDeleted:
      typeof data.communityBooksDeleted === "number" ? data.communityBooksDeleted : 0,
    error: data.state === "failed" && typeof data.error === "string" ? data.error : null,
  };
}
