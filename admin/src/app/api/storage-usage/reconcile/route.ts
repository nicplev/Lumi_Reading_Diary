import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { getAdminDb, getAdminStorage } from "@/lib/firebase-admin";
import { runStorageUsageReconcileNow } from "@lumi/server-ops";

// POST /api/storage-usage/reconcile
//
// Runs the same full-bucket scan the nightly reconcileStorageUsage cron
// runs, attributed to the super-admin who clicked the button. Used to
// seed opsMetrics/storageUsage after first deploy and to heal drift on
// demand.
export async function POST() {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const result = await runStorageUsageReconcileNow(
      getAdminDb(),
      getAdminStorage(),
      { uid: session.uid, email: session.email ?? undefined },
      { bucketName: process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET }
    );
    return NextResponse.json(result);
  } catch (error) {
    console.error("runStorageUsageReconcileNow failed:", error);
    return NextResponse.json(
      { error: "Failed to reconcile storage usage" },
      { status: 500 }
    );
  }
}
