import type { Firestore } from "firebase-admin/firestore";
import type { Auth } from "firebase-admin/auth";
import { FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import { logAuditEvent, ServerOpsValidationError, type Actor } from "./audit";

const paramsSchema = z.object({
  schoolId: z.string().min(1, "schoolId is required"),
  email: z.string().email("Valid email is required"),
  fullName: z.string().min(1, "Full name is required"),
  role: z.enum(["teacher", "schoolAdmin"]),
  classIds: z.array(z.string()).optional(),
});

export interface CreateSchoolUserParams {
  schoolId: string;
  email: string;
  fullName: string;
  role: "teacher" | "schoolAdmin";
  classIds?: string[];
}

export interface CreateSchoolUserResult {
  id: string;
}

// Creating a school user spans two systems: Firebase Auth (find-or-create the
// account by email) and Firestore (the school-scoped user doc, keyed by the
// Auth UID). Auth is passed explicitly so the module stays decoupled from any
// one app's firebase-admin singleton.
export async function createSchoolUser(
  auth: Auth,
  db: Firestore,
  actor: Actor,
  params: CreateSchoolUserParams
): Promise<CreateSchoolUserResult> {
  const parsed = paramsSchema.safeParse(params);
  if (!parsed.success) {
    throw new ServerOpsValidationError(
      parsed.error.issues.map((e) => e.message).join(", ")
    );
  }
  const { schoolId, email, fullName, role, classIds } = parsed.data;

  // Find-or-create the Firebase Auth user. getUserByEmail throws when there is
  // no match, which is the create path — not an error.
  let authUid: string;
  try {
    const existing = await auth.getUserByEmail(email);
    authUid = existing.uid;
  } catch {
    const newUser = await auth.createUser({ email, displayName: fullName });
    authUid = newUser.uid;
  }

  await db
    .collection("schools").doc(schoolId)
    .collection("users").doc(authUid)
    .set({
      email,
      fullName,
      role,
      classIds: classIds || [],
      linkedChildren: [],
      isActive: true,
      createdAt: FieldValue.serverTimestamp(),
    });

  await logAuditEvent(db, {
    action: "schoolUser.create",
    performedBy: actor.uid,
    performedByEmail: actor.email,
    targetType: "schoolUser",
    targetId: authUid,
    schoolId,
    after: { email, fullName, role, classIds: classIds ?? [] },
  }).catch((e) => {
    console.error("[server-ops] audit log failed for schoolUser.create", e);
  });

  return { id: authUid };
}
