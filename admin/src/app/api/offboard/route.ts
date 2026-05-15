import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { getAdminDb } from "@/lib/firebase-admin";
import {
  getOffboardPreview,
  offboardSchoolStep,
  ServerOpsValidationError,
} from "@lumi/server-ops";

export async function POST(request: Request) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const { action, schoolId, step } = body;
    const db = getAdminDb();

    if (action === "preview") {
      const preview = await getOffboardPreview(db, schoolId);
      if (!preview) {
        return NextResponse.json({ error: "School not found" }, { status: 404 });
      }
      return NextResponse.json(preview);
    }

    if (action === "execute") {
      const result = await offboardSchoolStep(
        db,
        { uid: session.uid, email: session.email ?? undefined },
        { schoolId, step }
      );
      return NextResponse.json(result);
    }

    return NextResponse.json({ error: "Invalid action" }, { status: 400 });
  } catch (error) {
    if (error instanceof ServerOpsValidationError) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    console.error("Offboard error:", error);
    return NextResponse.json(
      { error: "Failed to execute offboard action" },
      { status: 500 }
    );
  }
}
