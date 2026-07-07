import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import {
  updateOnboardingStatus,
  advanceOnboardingStep,
  linkOnboardingToSchool,
  updateOnboardingDetails,
  deleteOnboardingRequest,
  goLiveOnboarding,
  OnboardingBlockedError,
} from "@/lib/firestore/onboarding";
import {
  updateOnboardingStatusSchema,
  linkOnboardingToSchoolSchema,
  updateOnboardingDetailsSchema,
} from "@/lib/validations/onboarding";
import { logAuditEvent } from "@/lib/firestore/audit-log";

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
        logAuditEvent({ action: "onboarding.updateStatus", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "onboarding", targetId: id, after: body as Record<string, unknown> }).catch(console.error);
        return NextResponse.json({ success: true });
      }
      case "advanceStep": {
        const nextStep = await advanceOnboardingStep(id);
        logAuditEvent({ action: "onboarding.advanceStep", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "onboarding", targetId: id, after: body as Record<string, unknown> }).catch(console.error);
        return NextResponse.json({ success: true, nextStep });
      }
      case "linkSchool": {
        const parsed = linkOnboardingToSchoolSchema.parse(body);
        await linkOnboardingToSchool(id, parsed.schoolId);
        logAuditEvent({ action: "onboarding.linkSchool", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "onboarding", targetId: id, after: body as Record<string, unknown> }).catch(console.error);
        return NextResponse.json({ success: true });
      }
      case "updateDetails": {
        const parsed = updateOnboardingDetailsSchema.parse(body);
        await updateOnboardingDetails(id, parsed);
        logAuditEvent({ action: "onboarding.updateDetails", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "onboarding", targetId: id, after: parsed as Record<string, unknown> }).catch(console.error);
        return NextResponse.json({ success: true });
      }
      case "goLive": {
        try {
          const { provisioned } = await goLiveOnboarding(id, session.uid);
          logAuditEvent({ action: "onboarding.goLive", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "onboarding", targetId: id, after: { provisioned } }).catch(console.error);
          return NextResponse.json({ success: true, provisioned });
        } catch (e) {
          if (e instanceof OnboardingBlockedError) {
            return NextResponse.json(
              { error: e.message, blockers: e.blockers },
              { status: 400 }
            );
          }
          throw e;
        }
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
    await deleteOnboardingRequest(id);
    logAuditEvent({
      action: "onboarding.delete",
      performedBy: session.uid,
      performedByEmail: session.email ?? undefined,
      targetType: "onboarding",
      targetId: id,
    }).catch(console.error);
    return NextResponse.json({ success: true });
  } catch (error) {
    console.error("Delete onboarding error:", error);
    return NextResponse.json(
      { error: "Failed to delete onboarding request" },
      { status: 500 }
    );
  }
}
