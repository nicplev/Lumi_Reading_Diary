import { randomUUID } from "crypto";
import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { getAdminDb, getAdminStorage } from "@/lib/firebase-admin";
import { logAuditEvent } from "@/lib/firestore/audit-log";

// POST /api/community-books/[isbn]/cover
//
// Super-admin cover override. Writes to the app's canonical object path
// (community_books/covers/{isbn}.jpg) regardless of the uploaded mime —
// one object per ISBN, so overriding a teacher upload overwrites in
// place and never orphans a file; the stored contentType is what
// browsers actually honour. A fresh download token is minted (the
// overwrite invalidates the old one) and coverImageUrl on the doc is
// repointed, which is what the apps and portals read. The Flutter app
// only ever writes coverImageUrl when the doc has none, so an override
// sticks until the next override.

const ALLOWED_TYPES = ["image/jpeg", "image/png", "image/webp"];
// Matches the 2MB ceiling storage.rules enforces on client cover uploads.
const MAX_SIZE = 2 * 1024 * 1024;

export async function POST(
  request: Request,
  { params }: { params: Promise<{ isbn: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { isbn } = await params;
    if (!/^[0-9Xx-]{6,20}$/.test(isbn)) {
      return NextResponse.json({ error: "Invalid ISBN" }, { status: 400 });
    }

    const db = getAdminDb();
    const bookRef = db.collection("community_books").doc(isbn);
    const bookSnap = await bookRef.get();
    if (!bookSnap.exists) {
      return NextResponse.json({ error: "Book not found" }, { status: 404 });
    }

    const formData = await request.formData();
    const file = formData.get("file") as File | null;
    if (!file) {
      return NextResponse.json({ error: "No file provided" }, { status: 400 });
    }
    if (!ALLOWED_TYPES.includes(file.type)) {
      return NextResponse.json(
        { error: "Invalid file type. Allowed: JPEG, PNG, WebP" },
        { status: 400 }
      );
    }
    if (file.size > MAX_SIZE) {
      return NextResponse.json(
        { error: "File too large. Maximum size is 2MB" },
        { status: 400 }
      );
    }

    const filePath = `community_books/covers/${isbn}.jpg`;
    const bucket = getAdminStorage().bucket(
      process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET
    );
    const fileRef = bucket.file(filePath);
    const token = randomUUID();

    const buffer = Buffer.from(await file.arrayBuffer());
    await fileRef.save(buffer, {
      metadata: {
        contentType: file.type,
        metadata: { firebaseStorageDownloadTokens: token },
      },
    });

    const coverImageUrl =
      `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/` +
      `${encodeURIComponent(filePath)}?alt=media&token=${token}`;

    const previousUrl = (bookSnap.data()?.coverImageUrl as string) ?? null;
    await bookRef.update({
      coverImageUrl,
      coverImageUpdatedAt: new Date(),
      coverImageUpdatedBy: session.email ?? session.uid,
    });

    logAuditEvent({
      action: "communityBook.coverOverride",
      performedBy: session.uid,
      performedByEmail: session.email ?? undefined,
      targetType: "communityBook",
      targetId: isbn,
      after: { coverImageUrl } as Record<string, unknown>,
      metadata: { previousUrl, sizeBytes: file.size, contentType: file.type },
    }).catch(console.error);

    return NextResponse.json({ coverImageUrl });
  } catch (error) {
    console.error("Community book cover override error:", error);
    return NextResponse.json(
      { error: "Failed to upload cover" },
      { status: 500 }
    );
  }
}
