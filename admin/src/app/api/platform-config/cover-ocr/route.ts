import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { getAdminDb } from "@/lib/firebase-admin";
import {
  getCoverOcrFlag,
  setCoverOcrFlag,
  ServerOpsValidationError,
} from "@lumi/server-ops";

export async function GET() {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const flag = await getCoverOcrFlag(getAdminDb());
  return NextResponse.json(flag);
}

export async function PUT(request: Request) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  try {
    const body = await request.json();
    const flag = await setCoverOcrFlag(
      getAdminDb(),
      { uid: session.uid, email: session.email },
      { enabled: body.enabled === true, reason: body.reason }
    );
    return NextResponse.json(flag);
  } catch (err) {
    if (err instanceof ServerOpsValidationError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    throw err;
  }
}
