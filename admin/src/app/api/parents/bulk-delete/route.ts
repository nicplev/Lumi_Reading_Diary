import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { getAdminAuth, getAdminDb } from "@/lib/firebase-admin";
import { bulkDeleteParents, ServerOpsValidationError } from "@lumi/server-ops";

// Cross-cutting op: delete many parents in one call (each via the same full
// teardown as the single delete, freeing every email + MFA phone). Items carry
// their own schoolId since a selection can span schools.
export async function POST(request: Request) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const result = await bulkDeleteParents(
      getAdminAuth(),
      getAdminDb(),
      { uid: session.uid, email: session.email ?? undefined },
      { items: body.items }
    );
    return NextResponse.json(result);
  } catch (error) {
    if (error instanceof ServerOpsValidationError) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    console.error("Bulk parent delete error:", error);
    return NextResponse.json(
      { error: "Failed to bulk-delete parents" },
      { status: 500 }
    );
  }
}
