import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { getAdminDb } from "@/lib/firebase-admin";
import {
  getStorageAlertsConfig,
  setStorageAlertsConfig,
  ServerOpsValidationError,
} from "@lumi/server-ops";

export async function GET() {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const config = await getStorageAlertsConfig(getAdminDb());
  return NextResponse.json(config);
}

export async function PUT(request: Request) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const result = await setStorageAlertsConfig(
      getAdminDb(),
      { uid: session.uid, email: session.email ?? undefined },
      { warnBytes: body.warnBytes, criticalBytes: body.criticalBytes }
    );
    return NextResponse.json(result);
  } catch (error) {
    if (error instanceof ServerOpsValidationError) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    console.error("Set storage alerts config error:", error);
    return NextResponse.json(
      { error: "Failed to update storage alert thresholds" },
      { status: 500 }
    );
  }
}
