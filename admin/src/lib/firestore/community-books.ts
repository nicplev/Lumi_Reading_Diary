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

export interface CommunityBookListItem {
  isbn: string;
  title: string;
  author: string;
  coverImageUrl: string;
  readingLevel: string;
  source: string;
  contributedByName: string;
  contributedBySchoolId: string;
  createdAt: string;
}

export async function listCommunityBooks(): Promise<CommunityBookListItem[]> {
  const snapshot = await getAdminDb()
    .collection("community_books")
    .orderBy("createdAt", "desc")
    .get();

  return snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      isbn: doc.id,
      title: data.title ?? "",
      author: data.author ?? "",
      coverImageUrl: data.coverImageUrl ?? "",
      readingLevel: data.readingLevel ?? "",
      source: data.source ?? "",
      contributedByName: data.contributedByName ?? "",
      contributedBySchoolId: data.contributedBySchoolId ?? "",
      createdAt: toISO(data.createdAt),
    };
  });
}

export interface DeletionRequestListItem {
  id: string;
  isbn: string;
  bookTitle: string;
  bookAuthor: string;
  reason: string;
  requestedByName: string;
  schoolId: string;
  status: string;
  createdAt: string;
}

export async function listPendingDeletionRequests(): Promise<
  DeletionRequestListItem[]
> {
  const db = getAdminDb();

  const snapshot = await db
    .collectionGroup("deletionRequests")
    .where("status", "==", "pending")
    .orderBy("createdAt", "desc")
    .get();

  const items: DeletionRequestListItem[] = [];

  // Batch-fetch parent book data
  const bookFetches = snapshot.docs.map(async (doc) => {
    const data = doc.data();
    const parentRef = doc.ref.parent.parent;
    const isbn = parentRef?.id ?? "";

    let bookTitle = data.bookTitle ?? "";
    let bookAuthor = data.bookAuthor ?? "";
    if (parentRef && !bookTitle) {
      const bookDoc = await parentRef.get();
      if (bookDoc.exists) {
        const bookData = bookDoc.data()!;
        bookTitle = bookData.title ?? bookTitle;
        bookAuthor = bookData.author ?? bookAuthor;
      }
    }

    return {
      id: doc.id,
      isbn,
      bookTitle,
      bookAuthor,
      reason: data.reason ?? "",
      requestedByName: data.requestedByName ?? "",
      schoolId: data.schoolId ?? "",
      status: data.status ?? "pending",
      createdAt: toISO(data.createdAt),
    };
  });

  const results = await Promise.all(bookFetches);
  items.push(...results);

  return items;
}
