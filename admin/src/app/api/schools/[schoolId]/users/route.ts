import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { getAdminAuth, getAdminDb } from "@/lib/firebase-admin";
import { createSchoolUser, ServerOpsValidationError } from "@lumi/server-ops";

export async function POST(
  request: Request,
  { params }: { params: Promise<{ schoolId: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { schoolId } = await params;
    const body = await request.json();
    const result = await createSchoolUser(
      getAdminAuth(),
      getAdminDb(),
      { uid: session.uid, email: session.email ?? undefined },
      {
        schoolId,
        email: body.email,
        fullName: body.fullName,
        role: body.role,
        classIds: body.classIds,
      }
    );
    return NextResponse.json(result, { status: 201 });
  } catch (error) {
    if (error instanceof ServerOpsValidationError) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    console.error("Create school user error:", error);
    return NextResponse.json(
      { error: "Failed to create user" },
      { status: 500 }
    );
  }
}
