import { NextResponse } from "next/server";
import { z } from "zod";
import { verifySession } from "@/lib/auth";
import { getSanitisedDemoReseedStatus, runDemoReseed } from "@/lib/demo/reseed";
import {
  assertSameOrigin,
  consumeDemoRouteLimits,
  DemoRouteSecurityError,
} from "@/lib/demo/security";
import { DemoReseedConflictError } from "@lumi/server-ops";

const schema = z.object({ confirm: z.literal("REFRESH DEMO") }).strict();

export async function GET() {
  const session = await verifySession();
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  return NextResponse.json(await getSanitisedDemoReseedStatus());
}
export async function POST(request: Request) {
  const session = await verifySession();
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  try {
    assertSameOrigin(request);
    schema.parse(await request.json());
    await consumeDemoRouteLimits([
      { key: `reseed:actor:${session.uid}`, max: 2, windowMs: 60 * 60 * 1000 },
      { key: "reseed:global", max: 4, windowMs: 60 * 60 * 1000 },
    ]);
    const result = await runDemoReseed(
      { uid: session.uid, email: session.email },
      "manual"
    );
    return NextResponse.json({ success: true, ...result });
  } catch (error) {
    if (error instanceof DemoRouteSecurityError) {
      return NextResponse.json({ error: error.message }, { status: error.status });
    }
    if (error instanceof DemoReseedConflictError) {
      return NextResponse.json({ error: error.message }, { status: 409 });
    }
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: "Invalid refresh confirmation." }, { status: 400 });
    }
    console.error("Demo reseed failed", error);
    return NextResponse.json({ error: "Demo refresh failed. Check the status panel." }, { status: 500 });
  }
}
