import { adminDb } from '@/lib/firebase/admin';
import { FieldValue } from 'firebase-admin/firestore';
import type { Book } from '@/lib/types';

function toBook(doc: FirebaseFirestore.DocumentSnapshot): Book {
  const data = doc.data()!;
  return {
    id: doc.id,
    title: data.title ?? '',
    author: data.author,
    isbn: data.isbn,
    coverImageUrl: data.coverImageUrl,
    description: data.description,
    genres: data.genres ?? [],
    readingLevel: data.readingLevel,
    pageCount: data.pageCount,
    publisher: data.publisher,
    publishedDate: data.publishedDate?.toDate(),
    tags: data.tags ?? [],
    averageRating: data.averageRating,
    ratingCount: data.ratingCount ?? 0,
    isPopular: data.isPopular ?? false,
    timesRead: data.timesRead ?? 0,
    createdAt: data.createdAt?.toDate() ?? new Date(),
    addedBy: data.addedBy,
    metadata: data.metadata,
    scannedByTeacherIds: data.scannedByTeacherIds ?? [],
    timesAssignedSchoolWide: data.timesAssignedSchoolWide ?? 0,
  };
}

export async function getBooks(schoolId: string): Promise<Book[]> {
  const snap = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('books')
    .get();

  return snap.docs
    .map(toBook)
    .filter((b) => b.title && b.metadata?.placeholder !== true);
}

export async function getBook(schoolId: string, bookId: string): Promise<Book | null> {
  const doc = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('books')
    .doc(bookId)
    .get();
  if (!doc.exists) return null;
  return toBook(doc);
}

export async function createBook(
  schoolId: string,
  data: { title: string; author?: string; isbn?: string; readingLevel?: string; coverImageUrl?: string; createdBy: string }
): Promise<string> {
  const ref = adminDb.collection('schools').doc(schoolId).collection('books').doc();
  const now = FieldValue.serverTimestamp();

  await ref.set({
    title: data.title,
    author: data.author ?? null,
    isbn: data.isbn ?? null,
    isbnNormalized: data.isbn ? normalizeIsbn(data.isbn) : null,
    readingLevel: data.readingLevel ?? null,
    coverImageUrl: data.coverImageUrl ?? null,
    genres: [],
    tags: [],
    ratingCount: 0,
    isPopular: false,
    timesRead: 0,
    timesAssignedSchoolWide: 0,
    scannedByTeacherIds: [],
    addedBy: data.createdBy,
    createdAt: now,
    metadata: { source: 'web_portal', addedAt: new Date().toISOString() },
  });

  return ref.id;
}

export async function updateBook(
  schoolId: string,
  bookId: string,
  data: Partial<Pick<Book, 'title' | 'author' | 'isbn' | 'readingLevel' | 'coverImageUrl'>>
): Promise<void> {
  const update: Record<string, unknown> = { ...data };
  if (data.isbn !== undefined) {
    update.isbnNormalized = data.isbn ? normalizeIsbn(data.isbn) : null;
  }
  await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('books')
    .doc(bookId)
    .update(update);
}

export async function deleteBook(schoolId: string, bookId: string): Promise<void> {
  await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('books')
    .doc(bookId)
    .delete();
}

export async function lookupBookByIsbn(
  isbn: string,
  schoolId: string,
  actorId: string
): Promise<Book | null> {
  const normalized = normalizeIsbn(isbn);
  if (!normalized) return null;

  // 1. Check Firestore cache
  const snap = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('books')
    .where('isbnNormalized', '==', normalized)
    .limit(1)
    .get();

  if (!snap.empty) {
    const book = toBook(snap.docs[0]);
    if (book.title && book.metadata?.placeholder !== true) {
      return book;
    }
  }

  // 2. Google Books API
  const googleResult = await fetchFromGoogleBooks(normalized);
  if (googleResult) {
    // If no cover from Google, try Open Library
    if (!googleResult.coverImageUrl) {
      const olCover = await fetchOpenLibraryCover(normalized);
      if (olCover) googleResult.coverImageUrl = olCover;
    }
    // Cache to Firestore
    const bookId = await createBook(schoolId, {
      title: googleResult.title,
      author: googleResult.author,
      isbn: normalized,
      coverImageUrl: googleResult.coverImageUrl,
      createdBy: actorId,
    });
    return { ...toBookFromLookup(googleResult, normalized), id: bookId };
  }

  // 3. Open Library API
  const olResult = await fetchFromOpenLibrary(normalized);
  if (olResult) {
    const bookId = await createBook(schoolId, {
      title: olResult.title,
      author: olResult.author,
      isbn: normalized,
      coverImageUrl: olResult.coverImageUrl,
      createdBy: actorId,
    });
    return { ...toBookFromLookup(olResult, normalized), id: bookId };
  }

  return null;
}

// --- Internal helpers ---

function normalizeIsbn(isbn: string): string {
  return isbn.replace(/[-\s]/g, '').trim();
}

interface LookupResult {
  title: string;
  author?: string;
  coverImageUrl?: string;
  pageCount?: number;
  publisher?: string;
  description?: string;
}

function toBookFromLookup(result: LookupResult, isbn: string): Book {
  return {
    id: '',
    title: result.title,
    author: result.author,
    isbn,
    coverImageUrl: result.coverImageUrl,
    description: result.description,
    genres: [],
    readingLevel: undefined,
    pageCount: result.pageCount,
    publisher: result.publisher,
    tags: [],
    ratingCount: 0,
    isPopular: false,
    timesRead: 0,
    createdAt: new Date(),
    scannedByTeacherIds: [],
    timesAssignedSchoolWide: 0,
    metadata: { source: 'isbn_lookup' },
  };
}

async function fetchFromGoogleBooks(isbn: string): Promise<LookupResult | null> {
  try {
    const apiKey = process.env.GOOGLE_BOOKS_API_KEY || '';
    const keyParam = apiKey ? `&key=${apiKey}` : '';
    const res = await fetch(
      `https://www.googleapis.com/books/v1/volumes?q=isbn:${isbn}${keyParam}`,
      { signal: AbortSignal.timeout(5000) }
    );
    if (!res.ok) return null;
    const data = await res.json();
    if (!data.items?.length) return null;

    const vol = data.items[0].volumeInfo;
    return {
      title: vol.title ?? '',
      author: vol.authors?.join(', '),
      coverImageUrl: vol.imageLinks?.thumbnail?.replace('http:', 'https:'),
      pageCount: vol.pageCount,
      publisher: vol.publisher,
      description: vol.description,
    };
  } catch {
    return null;
  }
}

async function fetchFromOpenLibrary(isbn: string): Promise<LookupResult | null> {
  try {
    const res = await fetch(
      `https://openlibrary.org/isbn/${isbn}.json`,
      { signal: AbortSignal.timeout(5000) }
    );
    if (!res.ok) return null;
    const data = await res.json();

    let author: string | undefined;
    if (data.authors?.length) {
      try {
        const authorRes = await fetch(
          `https://openlibrary.org${data.authors[0].key}.json`,
          { signal: AbortSignal.timeout(3000) }
        );
        if (authorRes.ok) {
          const authorData = await authorRes.json();
          author = authorData.name;
        }
      } catch {
        // ignore author lookup failure
      }
    }

    return {
      title: data.title ?? '',
      author,
      coverImageUrl: `https://covers.openlibrary.org/b/isbn/${isbn}-M.jpg`,
      pageCount: data.number_of_pages,
      publisher: data.publishers?.[0],
    };
  } catch {
    return null;
  }
}

async function fetchOpenLibraryCover(isbn: string): Promise<string | null> {
  try {
    const url = `https://covers.openlibrary.org/b/isbn/${isbn}-M.jpg?default=false`;
    const res = await fetch(url, { method: 'HEAD', signal: AbortSignal.timeout(3000) });
    if (res.ok) return `https://covers.openlibrary.org/b/isbn/${isbn}-M.jpg`;
    return null;
  } catch {
    return null;
  }
}
