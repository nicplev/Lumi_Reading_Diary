import { randomUUID } from 'crypto';
import { adminDb, adminStorage } from '@/lib/firebase/admin';
import { Timestamp } from 'firebase-admin/firestore';
import { normalizeIsbn } from './isbn-assignment';

async function uploadCover(isbn: string, buffer: Buffer): Promise<{ url: string; path: string }> {
  const path = `community_books/covers/${isbn}.jpg`;
  const token = randomUUID();
  const bucket = adminStorage.bucket();
  await bucket.file(path).save(buffer, {
    contentType: 'image/jpeg',
    resumable: false,
    metadata: { metadata: { firebaseStorageDownloadTokens: token } },
  });
  // Firebase-style download URL (tokened) — same shape the app stores, and
  // covered by next.config's firebasestorage.googleapis.com remotePattern.
  const url = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(path)}?alt=media&token=${token}`;
  return { url, path };
}

export interface ContributeCommunityBookArgs {
  isbn: string;
  title: string;
  author?: string;
  readingLevel?: string;
  description?: string;
  pageCount?: number;
  publisher?: string;
  /** Raw image bytes to upload (client-resized JPEG from the Contribute flow). */
  coverBuffer?: Buffer;
  /** An already-hosted cover URL to store directly (from Add Book — the ISBN
   *  lookup's cover or a portal-uploaded image), avoiding a re-upload. */
  coverImageUrl?: string;
  contributedBy: string;
  contributedBySchoolId: string;
  contributedByName?: string;
}

/**
 * Contributes/updates a book in the global `community_books` catalog — the web
 * equivalent of the app's cover scanner. Mirrors CommunityBookService:
 * - doc id = normalized ISBN-13
 * - preserves contributedBy / contributedBySchoolId / createdAt on update
 * - only sets the cover when none exists yet (a web upload won't clobber a
 *   camera-scanned cover). The deterministic storage path is only written to
 *   when we actually set the cover, so an existing image is never overwritten.
 */
export async function upsertCommunityBook(
  args: ContributeCommunityBookArgs
): Promise<{ isbn: string; created: boolean; coverUpdated: boolean }> {
  const isbn = normalizeIsbn(args.isbn);
  if (!isbn) throw new Error('Enter a valid ISBN-10 or ISBN-13.');

  const ref = adminDb.collection('community_books').doc(isbn);
  const snap = await ref.get();
  const existing = snap.exists ? snap.data()! : null;
  const now = Timestamp.now();

  const title = args.title.trim();
  if (!title) throw new Error('Title is required.');

  // Only set the cover when we actually have one AND the catalog entry doesn't
  // already have one — a web add never clobbers an existing (e.g. camera-scanned)
  // cover. Prefer uploading raw bytes; otherwise store an already-hosted URL.
  const hasCover = !!args.coverBuffer || !!args.coverImageUrl;
  const willSetCover = hasCover && (!existing || !existing.coverImageUrl);
  let coverImageUrl: string | undefined;
  let coverStoragePath: string | undefined;
  if (willSetCover) {
    if (args.coverBuffer) {
      const up = await uploadCover(isbn, args.coverBuffer);
      coverImageUrl = up.url;
      coverStoragePath = up.path;
    } else if (args.coverImageUrl) {
      coverImageUrl = args.coverImageUrl;
    }
  }

  if (!existing) {
    await ref.set({
      isbn,
      title,
      titleNormalized: title.toLowerCase(),
      author: args.author?.trim() || null,
      coverImageUrl: coverImageUrl ?? null,
      coverStoragePath: coverStoragePath ?? null,
      description: args.description?.trim() || null,
      genres: [],
      readingLevel: args.readingLevel?.trim() || null,
      pageCount: args.pageCount ?? null,
      publisher: args.publisher?.trim() || null,
      tags: [],
      source: 'teacher_scan',
      contributedBy: args.contributedBy,
      contributedBySchoolId: args.contributedBySchoolId,
      contributedByName: args.contributedByName ?? null,
      createdAt: now,
      updatedAt: now,
      metadata: {
        coverSource: coverImageUrl ? (args.coverBuffer ? 'web_upload' : 'web_link') : null,
        hasCameraScannedCover: false,
      },
    });
    return { isbn, created: true, coverUpdated: !!coverImageUrl };
  }

  const update: Record<string, unknown> = {
    title,
    titleNormalized: title.toLowerCase(),
    updatedAt: now,
  };
  if (args.author?.trim()) update.author = args.author.trim();
  if (args.description?.trim()) update.description = args.description.trim();
  if (args.readingLevel?.trim()) update.readingLevel = args.readingLevel.trim();
  if (args.pageCount != null) update.pageCount = args.pageCount;
  if (args.publisher?.trim()) update.publisher = args.publisher.trim();
  if (coverImageUrl) {
    update.coverImageUrl = coverImageUrl;
    update.coverStoragePath = coverStoragePath;
  }

  await ref.update(update);
  return { isbn, created: false, coverUpdated: !!coverImageUrl };
}
