import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { getAdminDb } from "@/lib/firebase-admin";
import {
  getOffboardPreview,
  softDeactivateSchool,
  softDeactivateSubcollection,
} from "@/lib/firestore/offboard";
import { logAuditEvent } from "@/lib/firestore/audit-log";

export async function POST(request: Request) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const { action, schoolId, step } = body;

    if (!schoolId) {
      return NextResponse.json(
        { error: "schoolId is required" },
        { status: 400 }
      );
    }

    if (action === "preview") {
      const preview = await getOffboardPreview(schoolId);
      if (!preview) {
        return NextResponse.json(
          { error: "School not found" },
          { status: 404 }
        );
      }
      return NextResponse.json(preview);
    }

    if (action === "execute") {
      if (!step) {
        return NextResponse.json(
          { error: "step is required" },
          { status: 400 }
        );
      }

      // Check if school is already deactivated (prevent double-execution)
      const schoolDoc = await getAdminDb()
        .collection("schools")
        .doc(schoolId)
        .get();
      if (step === "school" && schoolDoc.exists && schoolDoc.data()?.isActive === false) {
        return NextResponse.json(
          { error: "School is already deactivated" },
          { status: 409 }
        );
      }

      let affected = 0;

      if (step === "school") {
        await softDeactivateSchool(schoolId);
        affected = 1;
      } else {
        affected = await softDeactivateSubcollection(schoolId, step);
      }

      logAuditEvent({
        action: "offboard.deactivate",
        performedBy: session.uid,
        performedByEmail: session.email ?? undefined,
        targetType: "school",
        targetId: schoolId,
        schoolId,
        after: { step, affected },
      }).catch(console.error);

      return NextResponse.json({ success: true, step, affected });
    }

    return NextResponse.json({ error: "Invalid action" }, { status: 400 });
  } catch (error) {
    console.error("Offboard error:", error);
    return NextResponse.json(
      { error: "Failed to execute offboard action" },
      { status: 500 }
    );
  }
}
