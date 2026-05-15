import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { getAdminAuth, getAdminDb } from "@/lib/firebase-admin";
import {
  manageSchoolUserAuth,
  ServerOpsValidationError,
} from "@lumi/server-ops";

export async function POST(
  request: Request,
  { params }: { params: Promise<{ schoolId: string; userId: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { schoolId, userId } = await params;
    const body = await request.json();
    const result = await manageSchoolUserAuth(
      getAdminAuth(),
      getAdminDb(),
      { uid: session.uid, email: session.email ?? undefined },
      { schoolId, userId, action: body.action }
    );
    return NextResponse.json(result);
  } catch (error) {
    if (error instanceof ServerOpsValidationError) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    console.error("User auth action error:", error);
    return NextResponse.json(
      { error: "Failed to perform auth action" },
      { status: 500 }
    );
  }
}
