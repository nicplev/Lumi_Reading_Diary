import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import {randomInt} from "node:crypto";

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

function generateCode(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";
  for (let i = 0; i < 8; i++) {
    code += chars.charAt(randomInt(chars.length));
  }
  return code;
}

export interface LinkCodeListItem {
  id: string;
  code: string;
  studentId: string;
  schoolId: string;
  status: string;
  createdAt: string;
  expiresAt?: string;
  createdBy: string;
  usedBy?: string;
  usedAt?: string;
}

export async function listLinkCodes(
  options?: { studentId?: string; schoolId?: string; status?: string }
): Promise<LinkCodeListItem[]> {
  let query: FirebaseFirestore.Query = getAdminDb()
    .collection("studentLinkCodes")
    .orderBy("createdAt", "desc");

  if (options?.studentId) {
    query = query.where("studentId", "==", options.studentId);
  }
  if (options?.schoolId) {
    query = query.where("schoolId", "==", options.schoolId);
  }
  if (options?.status) {
    query = query.where("status", "==", options.status);
  }

  const snapshot = await query.get();
  return snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      code: data.code,
      studentId: data.studentId,
      schoolId: data.schoolId,
      status: data.status,
      createdAt: toISO(data.createdAt),
      expiresAt: toISO(data.expiresAt) || undefined,
      createdBy: data.createdBy,
      usedBy: data.usedBy,
      usedAt: toISO(data.usedAt) || undefined,
    };
  });
}

export async function createLinkCode(data: {
  studentId: string;
  schoolId: string;
  createdBy: string;
  expiresInDays?: number;
}): Promise<{ id: string; code: string }> {
  const db = getAdminDb();

  // Refuse to issue a code for a non-existent student. Without this check
  // a code can be minted that points to nothing, and parents who try to
  // use it later hit "student-missing" from linkParentToStudent.
  const studentSnap = await db
    .collection("schools").doc(data.schoolId)
    .collection("students").doc(data.studentId)
    .get();
  if (!studentSnap.exists) {
    throw new Error(
      `createLinkCode: student ${data.schoolId}/${data.studentId} does not exist`
    );
  }

  let code = "";
  let isUnique = false;
  let attempts = 0;

  do {
    code = generateCode();
    const existing = await db
      .collection("studentLinkCodes")
      .where("code", "==", code)
      .limit(1)
      .get();
    isUnique = existing.empty;
    attempts++;
  } while (!isUnique && attempts < 10);

  if (!isUnique) {
    throw new Error("Failed to generate unique code");
  }

  const expiresInDays = data.expiresInDays ?? 7;
  const expiresAt = new Date();
  expiresAt.setDate(expiresAt.getDate() + expiresInDays);

  const docRef = await db.collection("studentLinkCodes").add({
    code,
    studentId: data.studentId,
    schoolId: data.schoolId,
    status: "active",
    createdAt: FieldValue.serverTimestamp(),
    expiresAt: Timestamp.fromDate(expiresAt),
    createdBy: data.createdBy,
  });

  return { id: docRef.id, code };
}

export async function revokeLinkCode(
  id: string,
  revokedBy: string,
  reason?: string
): Promise<void> {
  const updateData: Record<string, unknown> = {
    status: "revoked",
    revokedBy,
    revokedAt: FieldValue.serverTimestamp(),
  };
  if (reason) {
    updateData.revokeReason = reason;
  }

  await getAdminDb().collection("studentLinkCodes").doc(id).update(updateData);
}

export async function getStudentLinkCodes(
  studentId: string
): Promise<LinkCodeListItem[]> {
  return listLinkCodes({ studentId });
}
