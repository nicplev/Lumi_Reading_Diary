import { NextResponse, type NextRequest } from "next/server";
import { verifySession } from "@/lib/auth";
import { getSchoolAnalytics } from "@/lib/firestore/analytics";

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

    const now = new Date();
    const defaultStart = new Date(now);
    defaultStart.setDate(now.getDate() - now.getDay());
    defaultStart.setHours(0, 0, 0, 0);

    const startDate = searchParams.get("startDate")
      ? new Date(searchParams.get("startDate")!)
      : defaultStart;
    const endDate = searchParams.get("endDate")
      ? new Date(searchParams.get("endDate")!)
      : now;

    endDate.setHours(23, 59, 59, 999);

    const data = await getSchoolAnalytics(schoolId, { startDate, endDate });
    return NextResponse.json(data);
  } catch (error) {
    console.error("School analytics error:", error);
    return NextResponse.json(
      { error: "Failed to fetch analytics" },
      { status: 500 }
    );
  }
}
