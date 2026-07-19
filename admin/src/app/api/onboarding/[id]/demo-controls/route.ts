import { NextResponse } from "next/server";
import { z } from "zod";
import { verifySession } from "@/lib/auth";
import { demoControlPatchSchema } from "@/lib/demo/control-model";
import {
  DemoControlServiceError,
  updateLiveDemoControls,
} from "@/lib/demo/controls";
import {
  assertSameOrigin,
  consumeDemoRouteLimits,
  DemoRouteSecurityError,
} from "@/lib/demo/security";

const idSchema = z.string().trim().min(1).max(160);

function noStoreJson(body: unknown, status = 200): NextResponse {
  return NextResponse.json(body, {
    status,
    headers: { "cache-control": "no-store, max-age=0" },
  });
}

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const session = await verifySession();
  if (!session) return noStoreJson({ error: "Unauthorized" }, 401);

  try {
    assertSameOrigin(request);
    const onboardingId = idSchema.parse((await params).id);
    const patch = demoControlPatchSchema.parse(await request.json());
    await consumeDemoRouteLimits([
      {
        key: `controls:actor:${session.uid}`,
        max: 60,
        windowMs: 60 * 60 * 1000,
      },
      { key: "controls:global", max: 120, windowMs: 60 * 60 * 1000 },
    ]);

    const controls = await updateLiveDemoControls(
      { uid: session.uid, email: session.email },
      patch,
      { onboardingId },
    );
    return noStoreJson({ success: true, controls });
  } catch (error) {
    if (error instanceof DemoRouteSecurityError) {
      return noStoreJson({ error: error.message }, error.status);
    }
    if (error instanceof DemoControlServiceError) {
      return noStoreJson({ error: error.message }, error.status);
    }
    if (error instanceof z.ZodError) {
      return noStoreJson({ error: "Invalid demo control settings." }, 400);
    }
    console.error("Demo control update failed", error);
    return noStoreJson(
      { error: "The demo controls could not be updated. Check server logs and retry." },
      500,
    );
  }
}
