import { NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import { verifySession } from "@/lib/auth";
import { getAdminDb } from "@/lib/firebase-admin";
import {
  DemoPreflightError,
  type DemoPreflightResult,
} from "@/lib/demo/preflight-core";
import { runLiveDemoPreflight } from "@/lib/demo/preflight";
import { DEMO_SCHOOL_ID_DEFAULT } from "@/lib/firestore/demo-access";
import {
  assertSameOrigin,
  consumeDemoRouteLimits,
  DemoRouteSecurityError,
} from "@/lib/demo/security";

const requestSchema = z
  .object({ confirm: z.literal("RUN DEMO PREFLIGHT") })
  .strict();
const idSchema = z.string().trim().min(1).max(160);

function noStoreJson(body: unknown, status = 200): NextResponse {
  return NextResponse.json(body, {
    status,
    headers: { "cache-control": "no-store, max-age=0" },
  });
}

function readinessResponse(
  result: DemoPreflightResult,
  checkedByEmail?: string,
  error?: string,
) {
  return {
    ready: result.ready,
    state: result.ready ? ("ready" as const) : ("not_ready" as const),
    dayKey: result.dayKey,
    checkedAtISO: result.checkedAt,
    checkedByEmail: checkedByEmail ?? null,
    checks: result.checks,
    ...(error ? { error } : {}),
  };
}

async function saveReadinessReceipt(
  result: DemoPreflightResult,
  actor: { uid: string; email?: string },
  onboardingId: string,
): Promise<void> {
  const db = getAdminDb();
  const statusRef = db.doc("demoAccess/readinessStatus");
  const auditRef = db.collection("adminAuditLog").doc();
  const safeChecks = result.checks.map((check) => ({
    key: check.key,
    label: check.label,
    status: check.status,
    detail: check.detail,
  }));
  const batch = db.batch();
  batch.set(statusRef, {
    ready: result.ready,
    state: result.ready ? "ready" : "not_ready",
    dayKey: result.dayKey,
    checkedAt: FieldValue.serverTimestamp(),
    checkedBy: { uid: actor.uid, email: actor.email ?? null },
    onboardingId,
    checks: safeChecks,
  });
  batch.set(auditRef, {
    action: "demo.readinessCheck",
    performedBy: actor.uid,
    performedByEmail: actor.email ?? null,
    targetType: "onboarding",
    targetId: onboardingId,
    schoolId: DEMO_SCHOOL_ID_DEFAULT,
    after: {
      ready: result.ready,
      dayKey: result.dayKey,
      checks: safeChecks.map(({ key, status }) => ({ key, status })),
    },
    createdAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
}

export async function POST(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const session = await verifySession();
  if (!session) return noStoreJson({ error: "Unauthorized" }, 401);

  try {
    assertSameOrigin(request);
    requestSchema.parse(await request.json());
    const onboardingId = idSchema.parse((await params).id);
    await consumeDemoRouteLimits([
      {
        key: `readiness:actor:${session.uid}`,
        max: 6,
        windowMs: 60 * 60 * 1000,
      },
      { key: "readiness:global", max: 12, windowMs: 60 * 60 * 1000 },
    ]);

    const onboardingSnap = await getAdminDb()
      .collection("schoolOnboarding")
      .doc(onboardingId)
      .get();
    if (!onboardingSnap.exists || onboardingSnap.data()?.status !== "demo") {
      return noStoreJson(
        { error: "This readiness check is only available for a demo request." },
        409,
      );
    }

    try {
      const result = await runLiveDemoPreflight();
      await saveReadinessReceipt(
        result,
        { uid: session.uid, email: session.email },
        onboardingId,
      );
      return noStoreJson(readinessResponse(result, session.email));
    } catch (error) {
      if (error instanceof DemoPreflightError) {
        await saveReadinessReceipt(
          error.result,
          { uid: session.uid, email: session.email },
          onboardingId,
        );
        return noStoreJson(
          readinessResponse(error.result, session.email, error.message),
          409,
        );
      }
      throw error;
    }
  } catch (error) {
    if (error instanceof DemoRouteSecurityError) {
      return noStoreJson({ error: error.message }, error.status);
    }
    if (error instanceof z.ZodError) {
      return noStoreJson({ error: "Invalid readiness request." }, 400);
    }
    console.error("Demo readiness check failed", error);
    return noStoreJson(
      { error: "The readiness check could not run. Check server logs and retry." },
      500,
    );
  }
}
