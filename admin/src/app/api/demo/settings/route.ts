import { NextResponse } from "next/server";
import { z } from "zod";
import { verifySession } from "@/lib/auth";
import { getAdminDb } from "@/lib/firebase-admin";
import {
  demoControlPatchSchema,
  readDemoControlValues,
} from "@/lib/demo/control-model";
import {
  DemoControlServiceError,
  updateLiveDemoControls,
} from "@/lib/demo/controls";
import {
  assertSameOrigin,
  consumeDemoRouteLimits,
  DemoRouteSecurityError,
} from "@/lib/demo/security";
import {
  DEMO_SCHOOL_ID_DEFAULT,
  readDemoAccessConfig,
  sydneyDayKey,
} from "@/lib/firestore/demo-access";

const PRODUCTION_PROJECT_ID = "lumi-ninc-au";

function noStoreJson(body: unknown, status = 200): NextResponse {
  return NextResponse.json(body, {
    status,
    headers: { "cache-control": "no-store, max-age=0" },
  });
}

async function readTarget() {
  const configuredProject =
    process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID ?? PRODUCTION_PROJECT_ID;
  if (configuredProject !== PRODUCTION_PROJECT_ID) {
    throw new DemoRouteSecurityError(
      "Safety stop: the super-admin runtime targets the wrong Firebase project.",
      409,
    );
  }
  const config = await readDemoAccessConfig();
  if (config.schoolId !== DEMO_SCHOOL_ID_DEFAULT) {
    throw new DemoRouteSecurityError("Configured demo target is invalid.", 409);
  }

  const db = getAdminDb();
  const [schoolSnap, platformAudioSnap, stateSnap] = await Promise.all([
    db.doc(`schools/${DEMO_SCHOOL_ID_DEFAULT}`).get(),
    db.doc("platformConfig/comprehensionRecording").get(),
    db.doc("demoAccess/state").get(),
  ]);
  if (!schoolSnap.exists || schoolSnap.data()?.isDemo !== true) {
    throw new DemoRouteSecurityError(
      "Configured school is not marked as demo data.",
      409,
    );
  }
  const state = stateSnap.data();
  return {
    controls: readDemoControlValues(
      schoolSnap.data(),
      platformAudioSnap.data(),
    ),
    credentialActive:
      stateSnap.exists &&
      state?.dayKey === sydneyDayKey() &&
      state?.scrambledAt == null &&
      typeof state?.password === "string",
  };
}

export async function GET() {
  const session = await verifySession();
  if (!session) return noStoreJson({ error: "Unauthorized" }, 401);

  try {
    return noStoreJson(await readTarget());
  } catch (error) {
    if (error instanceof DemoRouteSecurityError) {
      return noStoreJson({ error: error.message }, error.status);
    }
    console.error("Read demo settings failed", error);
    return noStoreJson({ error: "Failed to read demo settings." }, 500);
  }
}

export async function PATCH(request: Request) {
  const session = await verifySession();
  if (!session) return noStoreJson({ error: "Unauthorized" }, 401);

  try {
    assertSameOrigin(request);
    const input = demoControlPatchSchema.parse(await request.json());
    await consumeDemoRouteLimits([
      {
        key: `settings:actor:${session.uid}`,
        max: 60,
        windowMs: 60 * 60 * 1000,
      },
      { key: "settings:global", max: 120, windowMs: 60 * 60 * 1000 },
    ]);
    const controls = await updateLiveDemoControls(
      { uid: session.uid, email: session.email },
      input,
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
      return noStoreJson({ error: "Invalid demo settings." }, 400);
    }
    console.error("Update demo settings failed", error);
    return noStoreJson({ error: "Failed to update demo settings." }, 500);
  }
}
