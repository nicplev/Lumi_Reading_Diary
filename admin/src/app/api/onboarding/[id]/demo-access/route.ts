import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import {
  provisionDemoAccessForOnboarding,
  sendDemoAccessEmail,
  DemoAccessError,
} from "@/lib/onboarding/demo-access";
import { demoAccessActionSchema } from "@/lib/validations/onboarding";
import { ServerOpsValidationError } from "@lumi/server-ops";

// POST /api/onboarding/[id]/demo-access
//   { action: "provision" }  → issue/reuse today's shared demo password
//   { action: "sendEmail" }  → queue the demo-details email to the requester
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
    const parsed = demoAccessActionSchema.parse(body);
    const actor = { uid: session.uid, email: session.email ?? undefined };

    if (parsed.action === "provision") {
      const result = await provisionDemoAccessForOnboarding(actor, id);
      return NextResponse.json({ success: true, ...result });
    }
    const result = await sendDemoAccessEmail(actor, id);
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
    if (error instanceof DemoAccessError) {
      return NextResponse.json({ error: error.message }, { status: error.status });
    }
    if (error instanceof ServerOpsValidationError) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    console.error("Demo-access error:", error);
    return NextResponse.json(
      { error: "Failed to complete the demo-access action" },
      { status: 500 }
    );
  }
}
