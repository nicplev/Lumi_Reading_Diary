import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { getAdminDb } from "@/lib/firebase-admin";
import {
  getComprehensionRecordingFlag,
  setComprehensionRecordingFlag,
  ServerOpsValidationError,
} from "@lumi/server-ops";

export async function GET() {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const flag = await getComprehensionRecordingFlag(getAdminDb());
  return NextResponse.json(flag);
}

export async function PUT(request: Request) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const result = await setComprehensionRecordingFlag(
      getAdminDb(),
      { uid: session.uid, email: session.email ?? undefined },
      { enabled: body.enabled, reason: body.reason }
    );
    return NextResponse.json(result);
  } catch (error) {
    if (error instanceof ServerOpsValidationError) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    console.error("Set comprehension recording flag error:", error);
    return NextResponse.json(
      { error: "Failed to update comprehension recording flag" },
      { status: 500 }
    );
  }
}
