import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { createOnboardingRequest } from "@/lib/firestore/onboarding";
import { createOnboardingSchema } from "@/lib/validations/onboarding";
import { logAuditEvent } from "@/lib/firestore/audit-log";

// POST /api/onboarding — create a pipeline request (operator/outbound lead).
export async function POST(request: Request) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const parsed = createOnboardingSchema.parse(body);
    const id = await createOnboardingRequest(parsed);
    logAuditEvent({
      action: "onboarding.create",
      performedBy: session.uid,
      performedByEmail: session.email ?? undefined,
      targetType: "onboarding",
      targetId: id,
      after: parsed as Record<string, unknown>,
    }).catch(console.error);
    return NextResponse.json({ id, success: true }, { status: 201 });
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
    console.error("Create onboarding error:", error);
    return NextResponse.json(
      { error: "Failed to create onboarding request" },
      { status: 500 }
    );
  }
}
