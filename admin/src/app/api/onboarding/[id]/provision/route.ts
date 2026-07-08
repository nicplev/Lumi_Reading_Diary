import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import {
  provisionSchoolFromOnboarding,
  OnboardingProvisionError,
} from "@/lib/onboarding/provision";
import { provisionSchoolSchema } from "@/lib/validations/onboarding";
import { ServerOpsValidationError } from "@lumi/server-ops";

// POST /api/onboarding/[id]/provision — create the school + comp subscription
// (activates access) + schoolAdmin account + invite link (+ optional join code),
// then link and advance the request to setupInProgress.
export async function POST(
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
    const parsed = provisionSchoolSchema.parse(body);
    const result = await provisionSchoolFromOnboarding(
      { uid: session.uid, email: session.email ?? undefined },
      { onboardingId: id, ...parsed }
    );
    return NextResponse.json({ success: true, ...result });
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
    if (
      error instanceof OnboardingProvisionError ||
      error instanceof ServerOpsValidationError
    ) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    console.error("Provision onboarding error:", error);
    return NextResponse.json(
      { error: "Failed to provision school" },
      { status: 500 }
    );
  }
}
