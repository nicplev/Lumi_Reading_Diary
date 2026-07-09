import { NextRequest, NextResponse } from 'next/server';
import { randomUUID } from 'crypto';
import { getSession } from '@/lib/auth/session';
import { adminStorage } from '@/lib/firebase/admin';

// Address the bucket explicitly — admin.ts initializes without a default
// storageBucket (same as the comprehension-audio route).
const BUCKET = process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET;

const MAX_BYTES = 5 * 1024 * 1024; // 5 MB
const EXT: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/gif': 'gif',
};

/**
 * Uploads a book-cover image and returns a stable Firebase download URL to store
 * in `book.coverImageUrl`. Lets staff drag-drop / pick a file instead of pasting
 * a URL. Server-side via the Admin SDK (bypasses Storage rules); the object is
 * tagged with a download token so the returned URL is readable without public
 * ACLs or URL signing (same mechanism as the client SDK's getDownloadURL).
 */
export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  if (!BUCKET) return NextResponse.json({ error: 'Storage is not configured' }, { status: 500 });

  try {
    const form = await request.formData();
    const file = form.get('file');
    if (!(file instanceof File)) {
      return NextResponse.json({ error: 'No image was provided' }, { status: 400 });
    }
    const ext = EXT[file.type];
    if (!ext) {
      return NextResponse.json({ error: 'Please upload a JPG, PNG, WebP or GIF image' }, { status: 400 });
    }
    if (file.size > MAX_BYTES) {
      return NextResponse.json({ error: 'Image must be 5 MB or smaller' }, { status: 400 });
    }

    const buffer = Buffer.from(await file.arrayBuffer());
    const token = randomUUID();
    const path = `bookCovers/${session.schoolId}/${randomUUID()}.${ext}`;
    await adminStorage
      .bucket(BUCKET)
      .file(path)
      .save(buffer, {
        resumable: false,
        metadata: {
          contentType: file.type,
          cacheControl: 'public, max-age=31536000',
          metadata: { firebaseStorageDownloadTokens: token },
        },
      });

    const url = `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(path)}?alt=media&token=${token}`;
    return NextResponse.json({ url });
  } catch {
    return NextResponse.json({ error: 'Failed to upload image' }, { status: 500 });
  }
}
