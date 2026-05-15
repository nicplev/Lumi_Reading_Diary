import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { getAdminDb } from "@/lib/firebase-admin";
import { grantDevAccess, ServerOpsValidationError } from "@lumi/server-ops";
import { listDevAccessEmails } from "@/lib/firestore/dev-access";

export async function GET() {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const emails = await listDevAccessEmails();
  return NextResponse.json({ emails });
}

export async function POST(request: Request) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const result = await grantDevAccess(
      getAdminDb(),
      { uid: session.uid, email: session.email ?? undefined },
      { email: body.email, note: body.note }
    );
    return NextResponse.json(result, { status: 201 });
  } catch (error) {
    if (error instanceof ServerOpsValidationError) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    console.error("Add dev access error:", error);
    return NextResponse.json(
      { error: "Failed to add dev access" },
      { status: 500 }
    );
  }
}
