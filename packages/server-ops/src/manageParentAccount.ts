import { createHash } from "crypto";
import type { Auth, UserRecord } from "firebase-admin/auth";
import type { Firestore } from "firebase-admin/firestore";
import { FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import { logAuditEvent, ServerOpsValidationError, type Actor } from "./audit";

// Parent accounts span three systems: Firebase Auth (the account, keyed by uid,
// which also owns the enrolled MFA phone factor), the school-scoped parent doc
// (schools/{schoolId}/parents/{uid} — the doc id IS the Auth uid), and the
// login lookup index (userSchoolIndex/{sha256(email|phone)}). A parent is also
// referenced from each linked student's `parentIds`. Terminating or recreating
// a parent for testing has to reason about all of them at once — otherwise a
// "deleted" parent's email/phone stays claimed in Auth and re-signup fails.

const paramsSchema = z.object({
  schoolId: z.string().min(1, "schoolId is required"),
  parentId: z.string().min(1, "parentId is required"),
  action: z.enum(["disable", "enable", "resetPassword", "delete"]),
});

export type ParentAccountAction =
  | "disable"
  | "enable"
  | "resetPassword"
  | "delete";

export interface ManageParentAccountParams {
  schoolId: string;
  parentId: string;
  action: ParentAccountAction;
}

export interface ParentDeletionSummary {
  authDeleted: boolean;
  parentDocDeleted: boolean;
  indexDocsDeleted: number;
  studentsUnlinked: number;
  /** Identifiers freed for reuse (email + phone), for the audit trail / UI. */
  freed: { email?: string; phones: string[] };
}

export interface ManageParentAccountResult {
  success: true;
  resetLink?: string;
  deletion?: ParentDeletionSummary;
}

export interface ParentAccountPreview {
  parentId: string;
  schoolId: string;
  fullName?: string;
  email?: string;
  phoneNumber?: string;
  /** Firestore soft-delete flag on the parent doc. */
  isActive: boolean;
  /** Whether a Firebase Auth user still exists for this uid. */
  authExists: boolean;
  /** Whether the Auth user is currently disabled (blocked from signing in). */
  authDisabled: boolean;
  /** E.164 numbers enrolled as MFA second factors, if any. */
  mfaPhones: string[];
  /** Number of students that reference this parent in `parentIds`. */
  linkedChildren: number;
  /** userSchoolIndex docs (email + phone keyed) that a delete would remove. */
  indexKeys: number;
}

function sha256Hex(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

/** Pull enrolled phone MFA factors off a UserRecord (E.164), if any. */
function mfaPhoneNumbers(user: UserRecord): string[] {
  const factors = user.multiFactor?.enrolledFactors ?? [];
  return factors
    .map((f) => (f as { phoneNumber?: string }).phoneNumber)
    .filter((p): p is string => typeof p === "string" && p.length > 0);
}

/** Best-effort fetch of the Auth record; null when the uid has no account. */
async function tryGetUser(auth: Auth, uid: string): Promise<UserRecord | null> {
  try {
    return await auth.getUser(uid);
  } catch {
    return null;
  }
}

/**
 * Collect every login-index key (email + phone) that could point at this
 * parent, drawn from BOTH the Firestore parent doc and the Auth record so a
 * delete cleans up even when the two have drifted. Normalised the same way the
 * signup path writes them: emails lowercased, phones kept as stored E.164.
 */
function collectIndexKeys(
  parentData: FirebaseFirestore.DocumentData | undefined,
  user: UserRecord | null
): { emails: Set<string>; phones: Set<string> } {
  const emails = new Set<string>();
  const phones = new Set<string>();

  const docEmail =
    typeof parentData?.email === "string" ? parentData.email : undefined;
  if (docEmail) emails.add(docEmail.toLowerCase());
  const docPhone =
    typeof parentData?.phoneNumber === "string"
      ? parentData.phoneNumber
      : undefined;
  if (docPhone) phones.add(docPhone);

  if (user?.email) emails.add(user.email.toLowerCase());
  if (user?.phoneNumber) phones.add(user.phoneNumber);
  for (const p of user ? mfaPhoneNumbers(user) : []) phones.add(p);

  return { emails, phones };
}

/**
 * Read-only preview of a parent account across Auth + Firestore, used to power
 * the delete-confirmation dialog. Returns null if the parent doc is missing.
 */
export async function getParentAccountPreview(
  auth: Auth,
  db: Firestore,
  params: { schoolId: string; parentId: string }
): Promise<ParentAccountPreview | null> {
  const { schoolId, parentId } = params;
  if (!schoolId || !parentId) {
    throw new ServerOpsValidationError("schoolId and parentId are required");
  }

  const parentRef = db
    .collection("schools").doc(schoolId)
    .collection("parents").doc(parentId);
  const parentSnap = await parentRef.get();
  if (!parentSnap.exists) return null;
  const data = parentSnap.data()!;

  const user = await tryGetUser(auth, parentId);
  const { emails, phones } = collectIndexKeys(data, user);

  const linkedChildren = Array.isArray(data.linkedChildren)
    ? (data.linkedChildren as string[]).length
    : 0;

  // Count only index docs that actually resolve to this parent (defensive: an
  // index re-pointed to another user must not be counted or later deleted).
  const indexKeys = await countOwnedIndexDocs(db, parentId, emails, phones);

  return {
    parentId,
    schoolId,
    fullName: typeof data.fullName === "string" ? data.fullName : undefined,
    email: typeof data.email === "string" ? data.email : undefined,
    phoneNumber:
      typeof data.phoneNumber === "string" ? data.phoneNumber : undefined,
    isActive: data.isActive ?? true,
    authExists: !!user,
    authDisabled: user?.disabled ?? false,
    mfaPhones: user ? mfaPhoneNumbers(user) : [],
    linkedChildren,
    indexKeys,
  };
}

/** Resolve userSchoolIndex docs (by hashed key) that belong to this uid. */
async function ownedIndexRefs(
  db: Firestore,
  parentId: string,
  emails: Set<string>,
  phones: Set<string>
): Promise<FirebaseFirestore.DocumentReference[]> {
  const keys = [...emails, ...phones];
  const refs = keys.map((k) =>
    db.collection("userSchoolIndex").doc(sha256Hex(k))
  );
  const snaps = await Promise.all(refs.map((r) => r.get()));
  return snaps
    .filter((s) => s.exists && s.data()?.userId === parentId)
    .map((s) => s.ref);
}

async function countOwnedIndexDocs(
  db: Firestore,
  parentId: string,
  emails: Set<string>,
  phones: Set<string>
): Promise<number> {
  return (await ownedIndexRefs(db, parentId, emails, phones)).length;
}

/**
 * Full, irreversible teardown of a parent account so its email + phone are
 * freed for reuse (the reason this exists: recreating test parents on the same
 * credentials). Order is chosen so a partial failure leaves the least mess:
 *   1. Auth user (releases the email + MFA phone claim) — the critical step.
 *   2. userSchoolIndex email/phone docs (login lookup) — owned entries only.
 *   3. Unlink from every student's parentIds.
 *   4. Parent doc + parentCount decrement.
 */
async function deleteParentAccount(
  auth: Auth,
  db: Firestore,
  schoolId: string,
  parentId: string
): Promise<ParentDeletionSummary> {
  const parentRef = db
    .collection("schools").doc(schoolId)
    .collection("parents").doc(parentId);
  const parentSnap = await parentRef.get();
  const data = parentSnap.exists ? parentSnap.data()! : undefined;

  const user = await tryGetUser(auth, parentId);
  const { emails, phones } = collectIndexKeys(data, user);

  // 1. Auth account — frees email + MFA phone. Idempotent: a missing user
  // (already deleted, or a legacy doc-id that was never an Auth uid) is fine.
  let authDeleted = false;
  if (user) {
    await auth.deleteUser(parentId);
    authDeleted = true;
  }

  // 2. Login index docs that resolve to this parent.
  const indexRefs = await ownedIndexRefs(db, parentId, emails, phones);
  await Promise.all(indexRefs.map((ref) => ref.delete()));

  // 3. Unlink from students. Use the parent's linkedChildren as the candidate
  // set, but arrayRemove is safe even if a child no longer references us.
  const linkedChildren = Array.isArray(data?.linkedChildren)
    ? (data!.linkedChildren as string[])
    : [];
  let studentsUnlinked = 0;
  if (linkedChildren.length > 0) {
    const results = await Promise.allSettled(
      linkedChildren.map((studentId) =>
        db
          .collection("schools").doc(schoolId)
          .collection("students").doc(studentId)
          .update({ parentIds: FieldValue.arrayRemove(parentId) })
      )
    );
    studentsUnlinked = results.filter((r) => r.status === "fulfilled").length;
  }

  // 4. Parent doc + best-effort counter.
  let parentDocDeleted = false;
  if (parentSnap.exists) {
    await parentRef.delete();
    parentDocDeleted = true;
    try {
      await db
        .collection("schools").doc(schoolId)
        .update({ parentCount: FieldValue.increment(-1) });
    } catch {
      // Non-critical counter.
    }
  }

  const freedEmail =
    (typeof data?.email === "string" && data.email) ||
    user?.email ||
    undefined;

  return {
    authDeleted,
    parentDocDeleted,
    indexDocsDeleted: indexRefs.length,
    studentsUnlinked,
    freed: { email: freedEmail, phones: [...phones] },
  };
}

/**
 * Perform one parent-account action, gating the Auth + Firestore mutations
 * behind a single validated call. `disable`/`enable` are reversible soft
 * terminations (block sign-in + flip the isActive flag); `resetPassword`
 * returns a copyable link; `delete` is the irreversible teardown above.
 */
export async function manageParentAccount(
  auth: Auth,
  db: Firestore,
  actor: Actor,
  params: ManageParentAccountParams
): Promise<ManageParentAccountResult> {
  const parsed = paramsSchema.safeParse(params);
  if (!parsed.success) {
    throw new ServerOpsValidationError(
      parsed.error.issues.map((e) => e.message).join(", ")
    );
  }
  const { schoolId, parentId, action } = parsed.data;

  const parentRef = db
    .collection("schools").doc(schoolId)
    .collection("parents").doc(parentId);

  let resetLink: string | undefined;
  let deletion: ParentDeletionSummary | undefined;

  if (action === "disable" || action === "enable") {
    const disabled = action === "disable";
    // Auth may not exist for legacy docs; the Firestore flag still matters.
    try {
      await auth.updateUser(parentId, { disabled });
    } catch (e) {
      if (!isUserNotFound(e)) throw e;
    }
    await parentRef.update({ isActive: !disabled }).catch(() => {
      // Parent doc may have been removed out from under us; not fatal.
    });
  } else if (action === "resetPassword") {
    const user = await tryGetUser(auth, parentId);
    const email = user?.email;
    if (!email) {
      throw new ServerOpsValidationError(
        "Parent has no email address on their Auth account"
      );
    }
    resetLink = await auth.generatePasswordResetLink(email);
  } else {
    deletion = await deleteParentAccount(auth, db, schoolId, parentId);
  }

  await logAuditEvent(db, {
    action: `parent.${action}`,
    performedBy: actor.uid,
    performedByEmail: actor.email,
    targetType: "parent",
    targetId: parentId,
    schoolId,
    after: deletion ? { action, ...deletion } : { action },
  }).catch((e) => {
    console.error(`[server-ops] audit log failed for parent.${action}`, e);
  });

  return {
    success: true,
    ...(resetLink ? { resetLink } : {}),
    ...(deletion ? { deletion } : {}),
  };
}

function isUserNotFound(e: unknown): boolean {
  return (
    typeof e === "object" &&
    e !== null &&
    (e as { code?: string }).code === "auth/user-not-found"
  );
}
