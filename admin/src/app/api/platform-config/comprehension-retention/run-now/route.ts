import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { getAdminDb, getAdminStorage } from "@/lib/firebase-admin";
import { runComprehensionRetentionNow } from "@lumi/server-ops";

// POST /api/platform-config/comprehension-retention/run-now
//
// Triggers the same cleanup loop the daily cron runs, attributed to the
// super-admin who clicked the button. Cleanup is idempotent — if a cron
// run already cleared everything older than retentionDays, this returns
// deletedCount: 0.
export async function POST() {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const result = await runComprehensionRetentionNow(
      getAdminDb(),
      getAdminStorage(),
      { uid: session.uid, email: session.email ?? undefined }
    );
    return NextResponse.json(result);
  } catch (error) {
    console.error("runComprehensionRetentionNow failed:", error);
    return NextResponse.json(
      { error: "Failed to run retention cleanup" },
      { status: 500 }
    );
  }
}
