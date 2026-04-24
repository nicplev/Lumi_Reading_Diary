import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";
import { getAdminStorage } from "@/lib/firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

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

export async function resolveDeletionRequest(
  isbn: string,
  requestId: string,
  action: "approved" | "rejected",
  resolvedBy: string
): Promise<void> {
  const db = getAdminDb();
  const requestRef = db
    .collection("community_books")
    .doc(isbn)
    .collection("deletionRequests")
    .doc(requestId);

  const requestDoc = await requestRef.get();
  if (!requestDoc.exists) {
    throw new Error("Deletion request not found");
  }
  if (requestDoc.data()?.status !== "pending") {
    throw new Error("Request has already been resolved");
  }

  if (action === "approved") {
    const batch = db.batch();

    // Update request status
    batch.update(requestRef, {
      status: "approved",
      resolvedAt: FieldValue.serverTimestamp(),
      resolvedBy,
    });

    // Delete the community book document
    const bookRef = db.collection("community_books").doc(isbn);
    batch.delete(bookRef);

    await batch.commit();

    // Delete copies from all school libraries (best-effort, outside batch)
    const schoolsSnap = await db.collection("schools").get();
    const schoolDeletes = schoolsSnap.docs.map(async (schoolDoc) => {
      const bookCopy = db
        .collection("schools")
        .doc(schoolDoc.id)
        .collection("books")
        .doc(`isbn_${isbn}`);
      const copyDoc = await bookCopy.get();
      if (copyDoc.exists) {
        await bookCopy.delete();
      }
    });
    await Promise.all(schoolDeletes);

    // Delete cover image from storage (best-effort)
    try {
      const bucket = getAdminStorage().bucket();
      const file = bucket.file(`community_books/covers/${isbn}.jpg`);
      await file.delete();
    } catch {
      // Cover may not exist — not critical
    }
  } else {
    // Rejected — just update the request status
    await requestRef.update({
      status: "rejected",
      resolvedAt: FieldValue.serverTimestamp(),
      resolvedBy,
    });
  }
}
