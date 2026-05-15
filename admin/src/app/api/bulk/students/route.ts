import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { getAdminDb } from "@/lib/firebase-admin";
import { bulkImportStudents, ServerOpsValidationError } from "@lumi/server-ops";

export async function POST(request: Request) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const result = await bulkImportStudents(
      getAdminDb(),
      { uid: session.uid, email: session.email ?? undefined },
      { schoolId: body.schoolId, students: body.students }
    );
    return NextResponse.json(result);
  } catch (error) {
    if (error instanceof ServerOpsValidationError) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    console.error("Bulk student import error:", error);
    return NextResponse.json(
      { error: "Failed to import students" },
      { status: 500 }
    );
  }
}
