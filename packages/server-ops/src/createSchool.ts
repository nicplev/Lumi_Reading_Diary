import type { Firestore } from "firebase-admin/firestore";
import { FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import { logAuditEvent, ServerOpsValidationError, type Actor } from "./audit";

const paramsSchema = z.object({
  name: z.string().min(1, "School name is required"),
  contactEmail: z.string().optional(),
  contactPhone: z.string().optional(),
  address: z.string().optional(),
  timezone: z.string().min(1, "Timezone is required"),
  subscriptionPlan: z.string().optional(),
  // Pre-existing asymmetry preserved: logoUrl / primaryColor / secondaryColor /
  // displayName are accepted and validated by the create API but are not
  // persisted by the underlying write. Treating that as out of scope here —
  // changing it is a separate fix from this Phase 5 extraction.
  logoUrl: z.string().url().optional().or(z.literal("")),
  primaryColor: z.string().optional(),
  secondaryColor: z.string().optional(),
  displayName: z.string().max(100).optional(),
});

export type CreateSchoolParams = z.input<typeof paramsSchema>;

export interface CreateSchoolResult {
  id: string;
}

export async function createSchool(
  db: Firestore,
  actor: Actor,
  params: CreateSchoolParams
): Promise<CreateSchoolResult> {
  const parsed = paramsSchema.safeParse(params);
  if (!parsed.success) {
    throw new ServerOpsValidationError(
      parsed.error.issues.map((e) => e.message).join(", ")
    );
  }
  const data = parsed.data;

  const docRef = await db.collection("schools").add({
    name: data.name,
    contactEmail: data.contactEmail || null,
    contactPhone: data.contactPhone || null,
    address: data.address || null,
    timezone: data.timezone,
    levelSchema: "aToZ",
    customLevels: [],
    subscriptionPlan: data.subscriptionPlan || null,
    isActive: true,
    studentCount: 0,
    teacherCount: 0,
    parentCount: 0,
    createdAt: FieldValue.serverTimestamp(),
    createdBy: actor.uid,
  });

  await logAuditEvent(db, {
    action: "school.create",
    performedBy: actor.uid,
    performedByEmail: actor.email,
    targetType: "school",
    targetId: docRef.id,
    schoolId: docRef.id,
    after: data,
  }).catch((e) => {
    console.error("[server-ops] audit log failed for school.create", e);
  });

  return { id: docRef.id };
}
