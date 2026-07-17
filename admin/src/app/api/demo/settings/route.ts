import { NextResponse } from "next/server";
import { z } from "zod";
import { verifySession } from "@/lib/auth";
import { getAdminDb } from "@/lib/firebase-admin";
import { readDemoAccessConfig } from "@/lib/firestore/demo-access";
import {
  assertSameOrigin,
  consumeDemoRouteLimits,
  DemoRouteSecurityError,
} from "@/lib/demo/security";
import { demoSchoolConstants } from "@lumi/server-ops";

const chip = z.string().trim().min(1).max(100);
const category = z.object({
  id: z.string().trim().min(1).max(80),
  name: z.string().trim().min(1).max(50),
  chips: z.array(chip).max(20),
}).strict();

const patchSchema = z.object({
  messagingEnabled: z.boolean().optional(),
  parentCommentsEnabled: z.boolean().optional(),
  freeTextEnabled: z.boolean().optional(),
  quickLoggingEnabled: z.boolean().optional(),
  customPresets: z.array(category).max(10).optional(),
}).strict().refine((value) => Object.keys(value).length > 0, "No settings supplied");

const DEFAULT_PRESETS = [
  { id: "default-1", name: "Encouragement", chips: ["Great job!", "Keep it up!", "Loved hearing you read!", "So proud of you!"] },
  { id: "default-2", name: "Reading Skills", chips: ["Sounded out words well", "Good finger tracking", "Read with expression", "Used picture clues"] },
  { id: "default-3", name: "Comprehension", chips: ["Understood the story well", "Asked great questions", "Made predictions", "Retold the story"] },
];

async function readTarget() {
  const config = await readDemoAccessConfig();
  if (config.schoolId !== demoSchoolConstants.schoolId) {
    throw new DemoRouteSecurityError("Configured demo target is invalid.", 409);
  }
  const ref = getAdminDb().collection("schools").doc(config.schoolId);
  const snap = await ref.get();
  if (!snap.exists || snap.data()?.isDemo !== true) {
    throw new DemoRouteSecurityError("Configured school is not marked as demo data.", 409);
  }
  return { ref, data: snap.data() ?? {}, schoolId: config.schoolId };
}

function safeSettings(data: FirebaseFirestore.DocumentData) {
  const settings = data.settings && typeof data.settings === "object" ? data.settings : {};
  const parent = settings.parentComments && typeof settings.parentComments === "object"
    ? settings.parentComments
    : {};
  return {
    messagingEnabled: settings.messaging?.enabled !== false,
    parentCommentsEnabled: parent.enabled !== false,
    freeTextEnabled: parent.freeTextEnabled !== false,
    quickLoggingEnabled: settings.quickLogging?.enabled !== false,
    customPresets: Array.isArray(parent.customPresets) ? parent.customPresets : DEFAULT_PRESETS,
    // Shared demo credentials cannot upload audio safely without a separate,
    // quota-enforced ingestion path. Do not imply real-school authority.
    comprehensionRecordingEnabled: false,
    comprehensionMode: "playback-only",
  };
}

export async function GET() {
  const session = await verifySession();
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  try {
    const target = await readTarget();
    return NextResponse.json(safeSettings(target.data));
  } catch (error) {
    if (error instanceof DemoRouteSecurityError) {
      return NextResponse.json({ error: error.message }, { status: error.status });
    }
    console.error("Read demo settings failed", error);
    return NextResponse.json({ error: "Failed to read demo settings." }, { status: 500 });
  }
}

export async function PATCH(request: Request) {
  const session = await verifySession();
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  try {
    assertSameOrigin(request);
    const input = patchSchema.parse(await request.json());
    await consumeDemoRouteLimits([
      { key: `settings:actor:${session.uid}`, max: 30, windowMs: 10 * 60 * 1000 },
      { key: "settings:global", max: 100, windowMs: 10 * 60 * 1000 },
    ]);
    const target = await readTarget();
    const update: Record<string, unknown> = { updatedAt: new Date() };
    if (input.messagingEnabled !== undefined) {
      update["settings.messaging.enabled"] = input.messagingEnabled;
    }
    if (input.parentCommentsEnabled !== undefined) {
      update["settings.parentComments.enabled"] = input.parentCommentsEnabled;
    }
    if (input.freeTextEnabled !== undefined) {
      update["settings.parentComments.freeTextEnabled"] = input.freeTextEnabled;
    }
    if (input.quickLoggingEnabled !== undefined) {
      update["settings.quickLogging.enabled"] = input.quickLoggingEnabled;
    }
    if (input.customPresets !== undefined) {
      update["settings.parentComments.customPresets"] = input.customPresets;
    }
    const db = getAdminDb();
    const auditRef = db.collection("adminAuditLog").doc();
    const batch = db.batch();
    batch.update(target.ref, update);
    batch.set(auditRef, {
      action: "demo.settingsUpdate",
      performedBy: session.uid,
      performedByEmail: session.email ?? null,
      targetType: "school",
      targetId: target.schoolId,
      schoolId: target.schoolId,
      after: input,
      createdAt: new Date(),
    });
    await batch.commit();
    const fresh = await target.ref.get();
    return NextResponse.json({ success: true, ...safeSettings(fresh.data() ?? {}) });
  } catch (error) {
    if (error instanceof DemoRouteSecurityError) {
      return NextResponse.json({ error: error.message }, { status: error.status });
    }
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: "Invalid demo settings." }, { status: 400 });
    }
    console.error("Update demo settings failed", error);
    return NextResponse.json({ error: "Failed to update demo settings." }, { status: 500 });
  }
}
