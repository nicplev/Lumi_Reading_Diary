import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { getAdminDb } from "@/lib/firebase-admin";
import {
  updateStudentReadingLevel,
  ServerOpsValidationError,
} from "@lumi/server-ops";

export async function POST(
  request: Request,
  { params }: { params: Promise<{ schoolId: string; studentId: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { schoolId, studentId } = await params;
    const body = await request.json();
    const result = await updateStudentReadingLevel(
      getAdminDb(),
      { uid: session.uid, email: session.email ?? undefined },
      {
        schoolId,
        studentId,
        level: body.level,
        levelIndex: body.levelIndex,
        reason: body.reason,
        source: body.source,
        changedByName: session.name ?? "Admin",
      }
    );
    return NextResponse.json(result);
  } catch (error) {
    if (error instanceof ServerOpsValidationError) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    console.error("Update reading level error:", error);
    return NextResponse.json(
      { error: "Failed to update reading level" },
      { status: 500 }
    );
  }
}
