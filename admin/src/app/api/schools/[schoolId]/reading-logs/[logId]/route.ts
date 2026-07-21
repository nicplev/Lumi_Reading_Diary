import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { getReadingLog } from "@/lib/firestore/reading-logs";

function validDocumentId(value: string): boolean {
  return value.length > 0 && value.length <= 256 && !value.includes("/");
}

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ schoolId: string; logId: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { schoolId, logId } = await params;
  if (!validDocumentId(schoolId) || !validDocumentId(logId)) {
    return NextResponse.json({ error: "Invalid reading log reference" }, { status: 400 });
  }

  try {
    const log = await getReadingLog(schoolId, logId);
    if (!log) {
      return NextResponse.json({ error: "Reading log not found" }, { status: 404 });
    }
    return NextResponse.json({ log });
  } catch (error) {
    console.error("Get reading log error", error);
    return NextResponse.json({ error: "Failed to get reading log" }, { status: 500 });
  }
}
