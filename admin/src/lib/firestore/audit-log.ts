import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";
import { FieldValue, Timestamp } from "firebase-admin/firestore";

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

export interface AuditLogEntry {
  id: string;
  action: string;
  performedBy: string;
  performedByEmail?: string;
  targetType: string;
  targetId: string;
  schoolId?: string;
  after?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
  createdAt: string;
}

export async function logAuditEvent(entry: {
  action: string;
  performedBy: string;
  performedByEmail?: string;
  targetType: string;
  targetId: string;
  schoolId?: string;
  after?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
}): Promise<void> {
  await getAdminDb()
    .collection("adminAuditLog")
    .add({
      ...entry,
      createdAt: FieldValue.serverTimestamp(),
    });
}

// Each single equality filter (action / targetType / schoolId /
// performedBy) is backed by a composite index with createdAt DESC in
// firestore.indexes.json. COMBINING two or more of those filters in one
// call needs a further composite — add it there before shipping such a
// caller, or the query throws FAILED_PRECONDITION.
export async function listAuditLogs(options?: {
  action?: string;
  targetType?: string;
  schoolId?: string;
  performedBy?: string;
  startDate?: string;
  endDate?: string;
  limit?: number;
}): Promise<AuditLogEntry[]> {
  let query: FirebaseFirestore.Query = getAdminDb()
    .collection("adminAuditLog")
    .orderBy("createdAt", "desc");

  if (options?.action) {
    query = query.where("action", "==", options.action);
  }
  if (options?.targetType) {
    query = query.where("targetType", "==", options.targetType);
  }
  if (options?.schoolId) {
    query = query.where("schoolId", "==", options.schoolId);
  }
  if (options?.performedBy) {
    query = query.where("performedBy", "==", options.performedBy);
  }
  if (options?.startDate) {
    query = query.where(
      "createdAt",
      ">=",
      Timestamp.fromDate(new Date(options.startDate))
    );
  }
  if (options?.endDate) {
    const endDate = new Date(options.endDate);
    endDate.setHours(23, 59, 59, 999);
    query = query.where("createdAt", "<=", Timestamp.fromDate(endDate));
  }

  query = query.limit(options?.limit ?? 200);

  const snapshot = await query.get();
  return snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      action: data.action ?? "",
      performedBy: data.performedBy ?? "",
      performedByEmail: data.performedByEmail,
      targetType: data.targetType ?? "",
      targetId: data.targetId ?? "",
      schoolId: data.schoolId,
      after: data.after,
      metadata: data.metadata,
      createdAt: toISO(data.createdAt),
    };
  });
}
