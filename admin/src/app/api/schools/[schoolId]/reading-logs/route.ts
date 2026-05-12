import { NextResponse, type NextRequest } from "next/server";
import { verifySession } from "@/lib/auth";
import { listReadingLogs } from "@/lib/firestore/reading-logs";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ schoolId: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { schoolId } = await params;
    const searchParams = request.nextUrl.searchParams;

    const logs = await listReadingLogs(schoolId, {
      classId: searchParams.get("classId") || undefined,
      studentId: searchParams.get("studentId") || undefined,
      status: searchParams.get("status") || undefined,
      startDate: searchParams.get("startDate") || undefined,
      endDate: searchParams.get("endDate") || undefined,
    });

    return NextResponse.json({ logs });
  } catch (error) {
    console.error("List reading logs error:", error);
    return NextResponse.json(
      { error: "Failed to list reading logs" },
      { status: 500 }
    );
  }
}
