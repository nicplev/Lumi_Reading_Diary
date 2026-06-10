import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { getAdminDb } from "@/lib/firebase-admin";
import {
  getComprehensionRetentionConfig,
  setComprehensionRetentionConfig,
  ServerOpsValidationError,
} from "@lumi/server-ops";

export async function GET() {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const config = await getComprehensionRetentionConfig(getAdminDb());
  return NextResponse.json(config);
}

export async function PUT(request: Request) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const result = await setComprehensionRetentionConfig(
      getAdminDb(),
      { uid: session.uid, email: session.email ?? undefined },
      { enabled: body.enabled, retentionDays: body.retentionDays }
    );
    return NextResponse.json(result);
  } catch (error) {
    if (error instanceof ServerOpsValidationError) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    console.error("Set comprehension retention config error:", error);
    return NextResponse.json(
      { error: "Failed to update comprehension retention config" },
      { status: 500 }
    );
  }
}
