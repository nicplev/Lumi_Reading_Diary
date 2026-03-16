import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import {
  updateOnboardingStatus,
  advanceOnboardingStep,
  linkOnboardingToSchool,
} from "@/lib/firestore/onboarding";
import {
  updateOnboardingStatusSchema,
  linkOnboardingToSchoolSchema,
} from "@/lib/validations/onboarding";

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { id } = await params;
    const body = await request.json();
    const action = body.action;

    switch (action) {
      case "updateStatus": {
        const parsed = updateOnboardingStatusSchema.parse(body);
        await updateOnboardingStatus(id, parsed.status);
        return NextResponse.json({ success: true });
      }
      case "advanceStep": {
        const nextStep = await advanceOnboardingStep(id);
        return NextResponse.json({ success: true, nextStep });
      }
      case "linkSchool": {
        const parsed = linkOnboardingToSchoolSchema.parse(body);
        await linkOnboardingToSchool(id, parsed.schoolId);
        return NextResponse.json({ success: true });
      }
      default:
        return NextResponse.json(
          { error: "Invalid action" },
          { status: 400 }
        );
    }
  } catch (error: unknown) {
    if (error instanceof Error && error.name === "ZodError") {
      return NextResponse.json(
        { error: "Validation failed", details: (error as unknown as { errors: unknown }).errors },
        { status: 400 }
      );
    }
    const message =
      error instanceof Error ? error.message : "Failed to update onboarding";
    console.error("Onboarding action error:", error);
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
