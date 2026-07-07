import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { getAdminAuth, getAdminDb } from "@/lib/firebase-admin";
import {
  getParentAccountPreview,
  manageParentAccount,
  ServerOpsValidationError,
} from "@lumi/server-ops";

// GET returns a read-only Auth+Firestore preview of the parent account, used to
// populate the delete-confirmation dialog (what will be freed / cleaned up).
export async function GET(
  _request: Request,
  { params }: { params: Promise<{ schoolId: string; parentId: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { schoolId, parentId } = await params;
    const preview = await getParentAccountPreview(getAdminAuth(), getAdminDb(), {
      schoolId,
      parentId,
    });
    if (!preview) {
      return NextResponse.json({ error: "Parent not found" }, { status: 404 });
    }
    return NextResponse.json(preview);
  } catch (error) {
    if (error instanceof ServerOpsValidationError) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    console.error("Parent account preview error:", error);
    return NextResponse.json(
      { error: "Failed to load parent account" },
      { status: 500 }
    );
  }
}

// POST performs one account action: disable / enable / resetPassword / delete.
// delete is an irreversible teardown that frees the email + phone for reuse.
export async function POST(
  request: Request,
  { params }: { params: Promise<{ schoolId: string; parentId: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { schoolId, parentId } = await params;
    const body = await request.json();
    const result = await manageParentAccount(
      getAdminAuth(),
      getAdminDb(),
      { uid: session.uid, email: session.email ?? undefined },
      { schoolId, parentId, action: body.action }
    );
    return NextResponse.json(result);
  } catch (error) {
    if (error instanceof ServerOpsValidationError) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    console.error("Parent account action error:", error);
    return NextResponse.json(
      { error: "Failed to perform parent account action" },
      { status: 500 }
    );
  }
}
