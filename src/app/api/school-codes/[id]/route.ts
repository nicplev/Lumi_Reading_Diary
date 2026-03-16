import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { revokeSchoolCode } from "@/lib/firestore/school-codes";

export async function DELETE(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { id } = await params;
    await revokeSchoolCode(id);
    return NextResponse.json({ success: true });
  } catch (error) {
    console.error("Revoke school code error:", error);
    return NextResponse.json(
      { error: "Failed to revoke school code" },
      { status: 500 }
    );
  }
}
