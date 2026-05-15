import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { listPendingDeletionRequests } from "@/lib/firestore/community-books";

export async function GET() {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const requests = await listPendingDeletionRequests();
    return NextResponse.json(requests);
  } catch (error) {
    console.error("Error listing deletion requests:", error);
    return NextResponse.json(
      { error: "Failed to list deletion requests" },
      { status: 500 }
    );
  }
}
