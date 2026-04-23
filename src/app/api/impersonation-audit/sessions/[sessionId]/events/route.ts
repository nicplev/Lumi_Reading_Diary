import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { listEvents } from "@/lib/firestore/impersonation-audit";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ sessionId: string }> },
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const { sessionId } = await params;
  const events = await listEvents(sessionId);
  return NextResponse.json({ events });
}
