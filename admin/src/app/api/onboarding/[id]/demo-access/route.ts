import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import {
  provisionDemoAccessForOnboarding,
  sendDemoAccessEmail,
  DemoAccessError,
} from "@/lib/onboarding/demo-access";
import { demoAccessActionSchema } from "@/lib/validations/onboarding";
import { ServerOpsValidationError } from "@lumi/server-ops";
import {
  assertSameOrigin,
  consumeDemoRouteLimits,
  DemoRouteSecurityError,
} from "@/lib/demo/security";

function noStoreJson(body: unknown, status = 200): NextResponse {
  return NextResponse.json(body, {
    status,
    headers: { "cache-control": "no-store, max-age=0" },
  });
}

// POST /api/onboarding/[id]/demo-access
//   { action: "provision" }  → issue/reuse today's shared demo password
//   { action: "sendEmail" }  → queue the demo-details email to the requester
export async function POST(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return noStoreJson({ error: "Unauthorized" }, 401);
  }

  try {
    assertSameOrigin(request);
    const { id } = await params;
    const body = await request.json();
    const parsed = demoAccessActionSchema.parse(body);
    const actor = { uid: session.uid, email: session.email ?? undefined };

    if (parsed.action === "provision") {
      await consumeDemoRouteLimits([
        { key: `provision:actor:${session.uid}`, max: 5, windowMs: 60 * 60 * 1000 },
        { key: "provision:global", max: 10, windowMs: 60 * 60 * 1000 },
      ]);
      const result = await provisionDemoAccessForOnboarding(actor, id);
      return noStoreJson({ success: true, ...result });
    }
    await consumeDemoRouteLimits([
      { key: `demo-email:actor:${session.uid}`, max: 10, windowMs: 60 * 60 * 1000 },
      { key: "demo-email:global", max: 30, windowMs: 60 * 60 * 1000 },
    ]);
    const result = await sendDemoAccessEmail(actor, id);
    return noStoreJson({ success: true, ...result });
  } catch (error: unknown) {
    if (error instanceof DemoRouteSecurityError) {
      return noStoreJson({ error: error.message }, error.status);
    }
    if (error instanceof Error && error.name === "ZodError") {
      return noStoreJson(
        {
          error: "Validation failed",
          details: (error as unknown as { errors: unknown }).errors,
        },
        400
      );
    }
    if (error instanceof DemoAccessError) {
      return noStoreJson({ error: error.message }, error.status);
    }
    if (error instanceof ServerOpsValidationError) {
      return noStoreJson({ error: error.message }, 400);
    }
    console.error("Demo-access error:", error);
    return noStoreJson(
      { error: "Failed to complete the demo-access action" },
      500
    );
  }
}
