import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import {randomInt} from "node:crypto";

function toISO(ts: unknown): string {
  if (!ts || typeof ts !== "object") return "";
  if ("toDate" in ts && typeof (ts as { toDate: unknown }).toDate === "function") {
    return (ts as { toDate: () => Date }).toDate().toISOString();
  }
  return "";
}

function generateCode(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";
  for (let i = 0; i < 10; i++) {
    code += chars.charAt(randomInt(chars.length));
  }
  return code;
}

export interface SchoolCodeListItem {
  id: string;
  code: string;
  schoolId: string;
  schoolName: string;
  isActive: boolean;
  createdAt: string;
  expiresAt?: string;
  usageCount: number;
  maxUsages?: number;
}

export async function listSchoolCodes(
  schoolId?: string
): Promise<SchoolCodeListItem[]> {
  let query: FirebaseFirestore.Query = getAdminDb()
    .collection("schoolCodes")
    .orderBy("createdAt", "desc");

  if (schoolId) {
    query = query.where("schoolId", "==", schoolId);
  }

  const snapshot = await query.get();
  return snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      code: data.code,
      schoolId: data.schoolId,
      schoolName: data.schoolName,
      isActive: data.isActive ?? true,
      createdAt: toISO(data.createdAt),
      expiresAt: toISO(data.expiresAt) || undefined,
      usageCount: data.usageCount ?? 0,
      maxUsages: data.maxUsages,
    };
  });
}

export async function createSchoolCode(data: {
  schoolId: string;
  schoolName: string;
  createdBy: string;
  maxUsages?: number;
  expiresInDays?: number;
}): Promise<{ id: string; code: string }> {
  const db = getAdminDb();

  let code: string = "";
  let isUnique = false;
  let attempts = 0;

  do {
    code = generateCode();
    const existing = await db
      .collection("schoolCodes")
      .where("code", "==", code)
      .limit(1)
      .get();
    isUnique = existing.empty;
    attempts++;
  } while (!isUnique && attempts < 10);

  if (!isUnique) {
    throw new Error("Failed to generate unique code");
  }

  const docData: Record<string, unknown> = {
    code,
    schoolId: data.schoolId,
    schoolName: data.schoolName,
    isActive: true,
    createdAt: FieldValue.serverTimestamp(),
    createdBy: data.createdBy,
    usageCount: 0,
  };

  docData.maxUsages = data.maxUsages ?? 100;

  const expiresAt = new Date();
  expiresAt.setDate(expiresAt.getDate() + (data.expiresInDays ?? 30));
  docData.expiresAt = Timestamp.fromDate(expiresAt);

  const docRef = await db.collection("schoolCodes").add(docData);
  return { id: docRef.id, code };
}

export async function revokeSchoolCode(id: string): Promise<void> {
  await getAdminDb().collection("schoolCodes").doc(id).update({
    isActive: false,
  });
}
