import "server-only";
import { createHash } from "crypto";
import { getAdminDb } from "@/lib/firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

// Collection schema:
//   /devAccessEmails/{emailHash}
//     email: string              (normalized: trimmed, lowercased)
//     addedBy: string            (uid of super-admin who added it)
//     addedByEmail?: string
//     addedAt: Timestamp
//     note?: string              (free-form, e.g. "QA teammate")
//
// Doc ID is the sha256 of the lowercased email. This gives us:
//   - Deterministic lookup without queries (doc(hash).get()) → the Flutter
//     client can check its own access with a single allowed `get` against
//     its own hash, no need to expose the full list.
//   - Automatic de-dup: adding the same email twice overwrites the same doc.

export interface DevAccessEmail {
  id: string;          // sha256 hash (also the doc id)
  email: string;
  addedBy: string;
  addedByEmail?: string;
  addedAt: string;     // ISO
  note?: string;
}

const COLLECTION = "devAccessEmails";

export function hashEmail(email: string): string {
  return createHash("sha256").update(email.trim().toLowerCase()).digest("hex");
}

function toISO(ts: unknown): string {
  if (!ts || typeof ts !== "object") return "";
  if ("toDate" in ts && typeof (ts as { toDate: unknown }).toDate === "function") {
    return (ts as { toDate: () => Date }).toDate().toISOString();
  }
  return "";
}

export async function listDevAccessEmails(): Promise<DevAccessEmail[]> {
  const snapshot = await getAdminDb()
    .collection(COLLECTION)
    .orderBy("addedAt", "desc")
    .get();

  return snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      email: data.email,
      addedBy: data.addedBy,
      addedByEmail: data.addedByEmail,
      addedAt: toISO(data.addedAt),
      note: data.note,
    };
  });
}

export async function addDevAccessEmail(input: {
  email: string;
  addedBy: string;
  addedByEmail?: string;
  note?: string;
}): Promise<DevAccessEmail> {
  const normalizedEmail = input.email.trim().toLowerCase();
  const id = hashEmail(normalizedEmail);
  const db = getAdminDb();
  const ref = db.collection(COLLECTION).doc(id);

  const existing = await ref.get();
  if (existing.exists) {
    throw new Error(`${normalizedEmail} already has dev access`);
  }

  const payload: Record<string, unknown> = {
    email: normalizedEmail,
    addedBy: input.addedBy,
    addedAt: FieldValue.serverTimestamp(),
  };
  if (input.addedByEmail) payload.addedByEmail = input.addedByEmail;
  if (input.note) payload.note = input.note.trim();

  await ref.set(payload);
  const fresh = await ref.get();
  const data = fresh.data() ?? {};
  return {
    id,
    email: normalizedEmail,
    addedBy: input.addedBy,
    addedByEmail: input.addedByEmail,
    addedAt: toISO(data.addedAt),
    note: input.note?.trim(),
  };
}

export async function updateDevAccessEmail(
  id: string,
  patch: { note?: string | null }
): Promise<void> {
  const update: Record<string, unknown> = {
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (patch.note === null) {
    update.note = FieldValue.delete();
  } else if (typeof patch.note === "string") {
    update.note = patch.note.trim();
  }
  await getAdminDb().collection(COLLECTION).doc(id).update(update);
}

export async function removeDevAccessEmail(id: string): Promise<void> {
  await getAdminDb().collection(COLLECTION).doc(id).delete();
}

export async function isDevAccessEmail(email: string): Promise<boolean> {
  if (!email) return false;
  const snap = await getAdminDb().collection(COLLECTION).doc(hashEmail(email)).get();
  return snap.exists;
}
