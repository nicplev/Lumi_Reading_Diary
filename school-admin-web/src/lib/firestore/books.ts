import { adminDb } from '@/lib/firebase/admin';
import { FieldValue } from 'firebase-admin/firestore';
import type { Book } from '@/lib/types';
// ISBN-13 normalizer (community_books is keyed by validated ISBN-13; the local
// normalizeIsbn below only strips separators).
import { normalizeIsbn as toIsbn13 } from './isbn-assignment';

// External book APIs (Google Books US, Open Library US) routinely take 3–6s
// from AU before the first byte; 12s matches the Flutter client's budget so the
// portal doesn't time out where the app succeeds.
const LOOKUP_TIMEOUT_MS = 12000;

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

/**
 * The inverse of getBooks: the placeholder / unresolved books it hides — added
 * by ISBN but never resolved to real metadata (no title, or an explicit
 * placeholder flag). Surfaced on the Library "Needs details" view so an admin
 * can complete or delete them instead of leaving them silently invisible.
 */
export async function getIncompleteBooks(schoolId: string): Promise<Book[]> {
  const snap = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('books')
    .get();

  return snap.docs
    .map(toBook)
    .filter((b) => !b.title || b.metadata?.placeholder === true);
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
  data: {
    title: string;
    author?: string;
    isbn?: string;
    readingLevel?: string;
    coverImageUrl?: string;
    description?: string;
    genres?: string[];
    pageCount?: number;
    publisher?: string;
    publishedDate?: Date;
    source?: string;
    createdBy: string;
  }
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
    description: data.description ?? null,
    genres: data.genres ?? [],
    pageCount: data.pageCount ?? null,
    publisher: data.publisher ?? null,
    publishedDate: data.publishedDate ?? null,
    tags: [],
    ratingCount: 0,
    isPopular: false,
    timesRead: 0,
    timesAssignedSchoolWide: 0,
    scannedByTeacherIds: [],
    addedBy: data.createdBy,
    createdAt: now,
    metadata: {
      source: data.source ?? 'web_portal',
      addedAt: new Date().toISOString(),
    },
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
  // A book given a real title is no longer an unresolved placeholder — clear the
  // flag (dot-path, so the rest of metadata is preserved) so it leaves the
  // "Needs details" view once completed.
  if (typeof data.title === 'string' && data.title.trim()) {
    update['metadata.placeholder'] = false;
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

  // 1.5 Shared community catalog (cross-school). The payoff of every school's
  //     Add Book: a cover another school contributed prefills here for free,
  //     without hitting an external API. Only short-circuits when the entry has
  //     a usable cover; otherwise fall through to the richer APIs below.
  const isbn13 = toIsbn13(isbn);
  if (isbn13) {
    const cDoc = await adminDb.collection('community_books').doc(isbn13).get();
    if (cDoc.exists) {
      const c = cDoc.data()!;
      if (c.title && c.coverImageUrl) {
        return {
          id: '',
          title: c.title,
          author: c.author ?? undefined,
          isbn: normalized,
          coverImageUrl: c.coverImageUrl,
          description: c.description ?? undefined,
          genres: Array.isArray(c.genres) ? c.genres : [],
          readingLevel: c.readingLevel ?? undefined,
          pageCount: c.pageCount ?? undefined,
          publisher: c.publisher ?? undefined,
          publishedDate: undefined,
          tags: [],
          ratingCount: 0,
          isPopular: false,
          timesRead: 0,
          createdAt: new Date(),
          scannedByTeacherIds: [],
          timesAssignedSchoolWide: 0,
          metadata: { source: 'community_catalog' },
        };
      }
    }
  }

  // 2. Google Books API
  const googleResult = await fetchFromGoogleBooks(normalized);
  if (googleResult) {
    // Partial-match fill: when Google is missing a cover and/or a description,
    // pull them from Open Library (queried by the same ISBN).
    const needsCover = !googleResult.coverImageUrl;
    const needsDescription = !googleResult.description?.trim();
    if (needsCover || needsDescription) {
      const ol = await fetchFromOpenLibrary(normalized, needsDescription);
      if (ol) {
        if (needsCover && ol.coverImageUrl) {
          googleResult.coverImageUrl = ol.coverImageUrl;
        }
        if (needsDescription && ol.description?.trim()) {
          googleResult.description = ol.description;
        }
      }
    }
    // Cache to Firestore
    const bookId = await createBook(schoolId, {
      title: googleResult.title,
      author: googleResult.author,
      isbn: normalized,
      coverImageUrl: googleResult.coverImageUrl,
      description: googleResult.description,
      genres: googleResult.genres,
      pageCount: googleResult.pageCount,
      publisher: googleResult.publisher,
      publishedDate: googleResult.publishedDate,
      source: 'google_books',
      createdBy: actorId,
    });
    return { ...toBookFromLookup(googleResult, normalized), id: bookId };
  }

  // 3. Open Library API
  const olResult = await fetchFromOpenLibrary(normalized, true);
  if (olResult) {
    const bookId = await createBook(schoolId, {
      title: olResult.title,
      author: olResult.author,
      isbn: normalized,
      coverImageUrl: olResult.coverImageUrl,
      description: olResult.description,
      genres: olResult.genres,
      pageCount: olResult.pageCount,
      publisher: olResult.publisher,
      publishedDate: olResult.publishedDate,
      source: 'open_library',
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
  genres?: string[];
  publishedDate?: Date;
}

function toBookFromLookup(result: LookupResult, isbn: string): Book {
  return {
    id: '',
    title: result.title,
    author: result.author,
    isbn,
    coverImageUrl: result.coverImageUrl,
    description: result.description,
    genres: result.genres ?? [],
    readingLevel: undefined,
    pageCount: result.pageCount,
    publisher: result.publisher,
    publishedDate: result.publishedDate,
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
      { signal: AbortSignal.timeout(LOOKUP_TIMEOUT_MS) }
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
      genres: Array.isArray(vol.categories) ? vol.categories : undefined,
      publishedDate: parseDateLoose(vol.publishedDate),
    };
  } catch {
    return null;
  }
}

async function fetchFromOpenLibrary(
  isbn: string,
  withDescription = false
): Promise<LookupResult | null> {
  try {
    // The search index returns author names directly and exposes `cover_i`
    // (present only when a cover exists) plus the Work `key` for descriptions.
    const res = await fetch(
      `https://openlibrary.org/search.json?isbn=${isbn}` +
        '&fields=key,title,author_name,publisher,number_of_pages_median,first_publish_year,subject,cover_i' +
        '&limit=1',
      { signal: AbortSignal.timeout(LOOKUP_TIMEOUT_MS) }
    );
    if (!res.ok) return null;
    const data = await res.json();
    const doc = data.docs?.[0];
    if (!doc?.title) return null;

    // Build the cover from `cover_i` only — never the unguarded /b/isbn URL,
    // which serves a grey placeholder (not a 404) when no cover is on file.
    const coverImageUrl =
      typeof doc.cover_i === 'number'
        ? `https://covers.openlibrary.org/b/id/${doc.cover_i}-M.jpg`
        : undefined;

    let description: string | undefined;
    if (withDescription && typeof doc.key === 'string') {
      description = await fetchOpenLibraryDescription(doc.key);
    }

    return {
      title: doc.title,
      author: doc.author_name?.[0],
      coverImageUrl,
      description,
      genres: Array.isArray(doc.subject) ? doc.subject.slice(0, 5) : undefined,
      pageCount: doc.number_of_pages_median,
      publisher: doc.publisher?.[0],
      publishedDate:
        typeof doc.first_publish_year === 'number'
          ? new Date(Date.UTC(doc.first_publish_year, 0, 1))
          : undefined,
    };
  } catch {
    return null;
  }
}

/// Fetch a synopsis from an Open Library Work record. `workKey` looks like
/// `/works/OL123W`. The `description` field is either a string or a
/// `{ type, value }` object. Returns undefined when missing/blank or on error.
async function fetchOpenLibraryDescription(
  workKey: string
): Promise<string | undefined> {
  try {
    const res = await fetch(`https://openlibrary.org${workKey}.json`, {
      signal: AbortSignal.timeout(LOOKUP_TIMEOUT_MS),
    });
    if (!res.ok) return undefined;
    const data = await res.json();
    const raw = data.description;
    const text = typeof raw === 'string' ? raw : raw?.value;
    const trimmed = typeof text === 'string' ? text.trim() : '';
    return trimmed.length > 0 ? trimmed : undefined;
  } catch {
    return undefined;
  }
}

/// Parse a loose date string (e.g. Google's "2024", "2024-03", "2024-03-15")
/// into a Date, or undefined if absent/invalid.
function parseDateLoose(value?: string): Date | undefined {
  if (!value) return undefined;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? undefined : d;
}
