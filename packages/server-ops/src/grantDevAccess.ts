import { createHash } from "crypto";
import type { Firestore } from "firebase-admin/firestore";
import { FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import { logAuditEvent, ServerOpsValidationError, type Actor } from "./audit";

const paramsSchema = z.object({
  email: z.string().email("A valid email is required").trim().toLowerCase(),
  note: z.string().trim().max(200).optional(),
});

export interface GrantDevAccessParams {
  email: string;
  note?: string;
}

export interface GrantDevAccessResult {
  id: string;
  email: string;
  addedBy: string;
  addedByEmail?: string;
  addedAt: string;
  note?: string;
}

// /devAccessEmails/{sha256(email)} is the canonical access-list collection;
// the Flutter client checks its own access by hashing its email and doing
// doc(hash).get() against rules that only permit reading the user's own hash.
function hashEmail(email: string): string {
  return createHash("sha256").update(email.trim().toLowerCase()).digest("hex");
}

function toISO(ts: unknown): string {
  if (!ts || typeof ts !== "object") return "";
  if (
    "toDate" in ts &&
    typeof (ts as { toDate: unknown }).toDate === "function"
  ) {
    return (ts as { toDate: () => Date }).toDate().toISOString();
  }
  return "";
}

export async function grantDevAccess(
  db: Firestore,
  actor: Actor,
  params: GrantDevAccessParams
): Promise<GrantDevAccessResult> {
  const parsed = paramsSchema.safeParse(params);
  if (!parsed.success) {
    throw new ServerOpsValidationError(
      parsed.error.issues[0]?.message ?? "Invalid input"
    );
  }
  const { email, note } = parsed.data;
  const id = hashEmail(email);

  const ref = db.collection("devAccessEmails").doc(id);
  const existing = await ref.get();
  if (existing.exists) {
    throw new ServerOpsValidationError(`${email} already has dev access`);
  }

  const payload: Record<string, unknown> = {
    email,
    addedBy: actor.uid,
    addedAt: FieldValue.serverTimestamp(),
  };
  if (actor.email) payload.addedByEmail = actor.email;
  if (note) payload.note = note;

  await ref.set(payload);
  const fresh = await ref.get();
  const data = fresh.data() ?? {};

  await logAuditEvent(db, {
    action: "devAccess.grant",
    performedBy: actor.uid,
    performedByEmail: actor.email,
    targetType: "devAccessEmail",
    targetId: id,
    after: { email, note },
  }).catch((e) => {
    console.error("[server-ops] audit log failed for devAccess.grant", e);
  });

  return {
    id,
    email,
    addedBy: actor.uid,
    addedByEmail: actor.email,
    addedAt: toISO(data.addedAt),
    note,
  };
}
