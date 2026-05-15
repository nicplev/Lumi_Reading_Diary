import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { getAdminDb, getAdminStorage } from "@/lib/firebase-admin";
import {
  resolveCommunityBookDeletion,
  ServerOpsValidationError,
} from "@lumi/server-ops";

export async function POST(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { id } = await params;
    const body = await request.json();
    const result = await resolveCommunityBookDeletion(
      getAdminDb(),
      getAdminStorage(),
      { uid: session.uid, email: session.email ?? undefined },
      { isbn: body.isbn, requestId: id, action: body.action }
    );
    return NextResponse.json(result);
  } catch (error) {
    if (error instanceof ServerOpsValidationError) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    console.error("Error resolving deletion request:", error);
    return NextResponse.json(
      { error: "Failed to resolve deletion request" },
      { status: 500 }
    );
  }
}
