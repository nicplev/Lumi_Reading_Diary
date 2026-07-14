import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";

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

export interface FeedbackListItem {
  id: string;
  userId: string;
  userRole: string;
  category: string;
  description: string;
  status: string;
  createdAt: string;
}

export async function listFeedback(limit?: number): Promise<FeedbackListItem[]> {
  let query: FirebaseFirestore.Query = getAdminDb()
    .collection("feedback")
    .orderBy("createdAt", "desc");
  if (limit) {
    query = query.limit(limit);
  }
  const snapshot = await query.get();

  return snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      userId: data.userId ?? "",
      userRole: data.userRole ?? "",
      category: data.category ?? "",
      description: data.description ?? "",
      status: data.status ?? "new",
      createdAt: toISO(data.createdAt),
    };
  });
}

export async function updateFeedbackStatus(
  id: string,
  status: string
): Promise<void> {
  await getAdminDb().collection("feedback").doc(id).update({ status });
}
