import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { getAdminDb } from "@/lib/firebase-admin";
import { createSchool, ServerOpsValidationError } from "@lumi/server-ops";
import {
  getCurrentAcademicYear,
  upsertSubscription,
} from "@/lib/firestore/school-subscriptions";
import { logAuditEvent } from "@/lib/firestore/audit-log";

export async function POST(request: Request) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const result = await createSchool(
      getAdminDb(),
      { uid: session.uid, email: session.email ?? undefined },
      body
    );

    // "Activate School Access now" toggle: create a free (comp) subscription
    // for the current year so the school is switched on from birth — future
    // parent-links auto-grant, no manual step. Off (a real prospect) leaves
    // billing for a deliberate later decision. Non-fatal: the school is
    // already created; a failed activation just leaves it inactive.
    let accessActivated = false;
    if (body?.activateAccess !== false) {
      try {
        const academicYear = await getCurrentAcademicYear();
        await upsertSubscription({
          schoolId: result.id,
          academicYear,
          status: "comp",
          updatedBy: session.uid,
        });
        accessActivated = true;
        logAuditEvent({
          action: "schoolSubscription.upsert",
          performedBy: session.uid,
          performedByEmail: session.email ?? undefined,
          targetType: "schoolSubscription",
          targetId: `${result.id}_${academicYear}`,
          schoolId: result.id,
          after: { status: "comp", academicYear, reason: "activate-on-create" },
        }).catch(console.error);
      } catch (subErr) {
        console.error("Activate-on-create subscription failed:", subErr);
      }
    }

    return NextResponse.json({ ...result, accessActivated }, { status: 201 });
  } catch (error) {
    if (error instanceof ServerOpsValidationError) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    console.error("Create school error:", error);
    return NextResponse.json(
      { error: "Failed to create school" },
      { status: 500 }
    );
  }
}
