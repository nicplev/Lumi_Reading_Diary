import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import {
  cascadeBookRemovalForSchool,
  normalizeIsbn,
} from "@lumi/server-ops";

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

export interface BookListItem {
  id: string;
  title: string;
  author?: string;
  isbn?: string;
  coverImageUrl?: string;
  readingLevel?: string;
  genres: string[];
  isPopular: boolean;
  timesRead: number;
  ratingCount: number;
  averageRating?: number;
  createdAt: string;
}

export interface BookDetail extends BookListItem {
  description?: string;
  pageCount?: number;
  publisher?: string;
  publishedDate?: string;
  tags: string[];
  addedBy?: string;
  scannedByTeacherIds: string[];
  timesAssignedSchoolWide: number;
  metadata?: Record<string, unknown>;
}

export async function listBooks(
  schoolId: string,
  options?: {
    readingLevel?: string;
    genre?: string;
    isPopular?: boolean;
    limit?: number;
  }
): Promise<BookListItem[]> {
  let query: FirebaseFirestore.Query = getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("books")
    .orderBy("createdAt", "desc");

  if (options?.readingLevel) {
    query = query.where("readingLevel", "==", options.readingLevel);
  }
  if (options?.isPopular !== undefined) {
    query = query.where("isPopular", "==", options.isPopular);
  }
  if (options?.limit) {
    query = query.limit(options.limit);
  }

  const snapshot = await query.get();
  return snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      title: data.title,
      author: data.author,
      isbn: data.isbn,
      coverImageUrl: data.coverImageUrl,
      readingLevel: data.readingLevel,
      genres: (data.genres as string[]) ?? [],
      isPopular: data.isPopular ?? false,
      timesRead: data.timesRead ?? 0,
      ratingCount: data.ratingCount ?? 0,
      averageRating: data.averageRating,
      createdAt: toISO(data.createdAt),
    };
  });
}

export async function getBook(
  schoolId: string,
  bookId: string
): Promise<BookDetail | null> {
  const doc = await getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("books")
    .doc(bookId)
    .get();
  if (!doc.exists) return null;

  const data = doc.data()!;
  return {
    id: doc.id,
    title: data.title,
    author: data.author,
    isbn: data.isbn,
    coverImageUrl: data.coverImageUrl,
    readingLevel: data.readingLevel,
    genres: (data.genres as string[]) ?? [],
    isPopular: data.isPopular ?? false,
    timesRead: data.timesRead ?? 0,
    ratingCount: data.ratingCount ?? 0,
    averageRating: data.averageRating,
    description: data.description,
    pageCount: data.pageCount,
    publisher: data.publisher,
    publishedDate: data.publishedDate,
    tags: (data.tags as string[]) ?? [],
    addedBy: data.addedBy,
    scannedByTeacherIds: (data.scannedByTeacherIds as string[]) ?? [],
    timesAssignedSchoolWide: data.timesAssignedSchoolWide ?? 0,
    metadata: data.metadata,
    createdAt: toISO(data.createdAt),
  };
}

export async function createBook(
  schoolId: string,
  data: {
    title: string;
    author?: string;
    isbn?: string;
    coverImageUrl?: string;
    description?: string;
    genres?: string[];
    readingLevel?: string;
    pageCount?: number;
    publisher?: string;
    tags?: string[];
    addedBy?: string;
  }
): Promise<string> {
  const docRef = await getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("books")
    .add({
      title: data.title,
      author: data.author || null,
      isbn: data.isbn || null,
      coverImageUrl: data.coverImageUrl || null,
      description: data.description || null,
      genres: data.genres ?? [],
      readingLevel: data.readingLevel || null,
      pageCount: data.pageCount ?? null,
      publisher: data.publisher || null,
      tags: data.tags ?? [],
      isPopular: false,
      timesRead: 0,
      ratingCount: 0,
      scannedByTeacherIds: [],
      timesAssignedSchoolWide: 0,
      addedBy: data.addedBy || null,
      createdAt: FieldValue.serverTimestamp(),
    });
  return docRef.id;
}

export async function updateBook(
  schoolId: string,
  bookId: string,
  data: Record<string, unknown>
): Promise<void> {
  await getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("books")
    .doc(bookId)
    .update(data);
}

/**
 * Deletes a school-library book and retires it from that school's allocations.
 *
 * Without the cascade the book document disappears while students keep an
 * assignment pointing at it — a title with no library entry. Allocations may
 * reference the book by ISBN or by this document id, so both are matched.
 *
 * Returns the number of allocations updated so the caller can record it.
 */
export async function deleteBook(
  schoolId: string,
  bookId: string,
  actorUid: string
): Promise<{ allocationsUpdated: number }> {
  const db = getAdminDb();
  const bookRef = db
    .collection("schools")
    .doc(schoolId)
    .collection("books")
    .doc(bookId);

  // Read the ISBN before deleting — afterwards it is unrecoverable.
  const snapshot = await bookRef.get();
  const isbn = normalizeIsbn(
    (snapshot.data()?.isbn as unknown) ??
      (bookId.startsWith("isbn_") ? bookId.slice("isbn_".length) : null)
  );

  await bookRef.delete();

  const allocationsUpdated = await cascadeBookRemovalForSchool(
    db,
    schoolId,
    { isbn, bookId },
    {
      removedAt: new Date(),
      removedBy: actorUid,
      reason: "school_library_book_deleted",
    }
  );

  return { allocationsUpdated };
}

export async function getBookCount(schoolId: string): Promise<number> {
  const snapshot = await getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("books")
    .count()
    .get();
  return snapshot.data().count;
}
