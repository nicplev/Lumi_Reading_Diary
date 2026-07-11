import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getBooks, createBook, updateBook, findBookIdByIsbn } from '@/lib/firestore/books';
import { upsertCommunityBook } from '@/lib/firestore/community-books';
import { z } from 'zod';

function serializeBook(b: Record<string, unknown>) {
  return {
    ...b,
    createdAt: b.createdAt instanceof Date ? b.createdAt.toISOString() : b.createdAt,
    publishedDate: b.publishedDate instanceof Date ? b.publishedDate.toISOString() : b.publishedDate ?? null,
  };
}

export async function GET() {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const books = await getBooks(session.schoolId);
    return NextResponse.json(books.map((b) => serializeBook(b as unknown as Record<string, unknown>)));
  } catch {
    return NextResponse.json({ error: 'Failed to fetch books' }, { status: 500 });
  }
}

const createBookSchema = z.object({
  title: z.string().min(1, 'Title is required'),
  author: z.string().optional(),
  isbn: z.string().optional(),
  readingLevel: z.string().optional(),
  coverImageUrl: z.string().optional(),
});

export async function POST(request: NextRequest) {
  const session = await getSession({ requireMutable: true });
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const body = await request.json();
    const data = createBookSchema.parse(body);

    // Dedup by ISBN. The ISBN "Lookup" already caches the resolved book into the
    // school library, so a plain create here would leave two copies of the same
    // book. If one already exists for this ISBN, update it (e.g. with a freshly
    // uploaded cover) and reuse it instead of adding a duplicate.
    const existingId = data.isbn ? await findBookIdByIsbn(session.schoolId, data.isbn) : null;
    let id: string;
    if (existingId) {
      const patch: Parameters<typeof updateBook>[2] = { title: data.title };
      if (data.author) patch.author = data.author;
      if (data.isbn) patch.isbn = data.isbn;
      if (data.readingLevel) patch.readingLevel = data.readingLevel;
      if (data.coverImageUrl) patch.coverImageUrl = data.coverImageUrl;
      await updateBook(session.schoolId, existingId, patch);
      id = existingId;
    } else {
      id = await createBook(session.schoolId, { ...data, createdBy: session.uid });
    }

    // Self-populating shared catalog: every ISBN'd book a school adds also seeds
    // the global community_books catalog (cover + core details) so any Lumi
    // school/app can scan or find it later. Non-destructive (won't overwrite an
    // existing cover) and best-effort — never block the school's own add.
    if (data.isbn) {
      try {
        await upsertCommunityBook({
          isbn: data.isbn,
          title: data.title,
          author: data.author,
          readingLevel: data.readingLevel,
          coverImageUrl: data.coverImageUrl,
          contributedBy: session.uid,
          contributedBySchoolId: session.schoolId,
        });
      } catch {
        /* best-effort — the book is already safely in the school library */
      }
    }

    return NextResponse.json({ id }, { status: 201 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to create book' }, { status: 500 });
  }
}
