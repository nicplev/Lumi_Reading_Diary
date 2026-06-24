import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { getSchool } from "@/lib/firestore/schools";
import {
  getCurrentAcademicYear,
  getSubscriptionsForSchool,
  listSubscriptionsForYear,
  upsertSubscription,
} from "@/lib/firestore/school-subscriptions";
import { upsertSubscriptionSchema } from "@/lib/validations/school-subscription";
import { logAuditEvent } from "@/lib/firestore/audit-log";

// GET /api/school-subscriptions?schoolId=...        -> all rows for one school
// GET /api/school-subscriptions?academicYear=2026   -> all schools for one year
//   (defaults academicYear to the current year when neither is given)
export async function GET(request: Request) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { searchParams } = new URL(request.url);
    const schoolId = searchParams.get("schoolId");
    if (schoolId) {
      const rows = await getSubscriptionsForSchool(schoolId);
      return NextResponse.json({ subscriptions: rows });
    }

    const yearParam = searchParams.get("academicYear");
    const academicYear = yearParam
      ? Number(yearParam)
      : await getCurrentAcademicYear();
    const rows = await listSubscriptionsForYear(academicYear);
    return NextResponse.json({ academicYear, subscriptions: rows });
  } catch (error) {
    console.error("List subscriptions error:", error);
    return NextResponse.json(
      { error: "Failed to load subscriptions" },
      { status: 500 }
    );
  }
}

// POST /api/school-subscriptions — create/update the {schoolId}_{year} row.
export async function POST(request: Request) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const parsed = upsertSubscriptionSchema.parse(body);

    const school = await getSchool(parsed.schoolId);
    if (!school) {
      return NextResponse.json({ error: "School not found" }, { status: 404 });
    }

    const id = await upsertSubscription({
      ...parsed,
      updatedBy: session.uid,
    });

    logAuditEvent({
      action: "schoolSubscription.upsert",
      performedBy: session.uid,
      performedByEmail: session.email ?? undefined,
      targetType: "schoolSubscription",
      targetId: id,
      schoolId: parsed.schoolId,
      after: parsed as Record<string, unknown>,
    }).catch(console.error);

    return NextResponse.json({ id, success: true }, { status: 200 });
  } catch (error: unknown) {
    if (error instanceof Error && error.name === "ZodError") {
      return NextResponse.json(
        {
          error: "Validation failed",
          details: (error as unknown as { errors: unknown }).errors,
        },
        { status: 400 }
      );
    }
    console.error("Upsert subscription error:", error);
    return NextResponse.json(
      { error: "Failed to save subscription" },
      { status: 500 }
    );
  }
}
