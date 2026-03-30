import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getBook, updateBook, deleteBook } from '@/lib/firestore/books';
import { z } from 'zod';

export async function GET(_request: NextRequest, { params }: { params: Promise<{ bookId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { bookId } = await params;
  const book = await getBook(session.schoolId, bookId);
  if (!book) return NextResponse.json({ error: 'Book not found' }, { status: 404 });

  return NextResponse.json({
    ...book,
    createdAt: book.createdAt.toISOString(),
    publishedDate: book.publishedDate?.toISOString() ?? null,
  });
}

const updateBookSchema = z.object({
  title: z.string().min(1).optional(),
  author: z.string().optional(),
  isbn: z.string().optional(),
  readingLevel: z.string().optional(),
  coverImageUrl: z.string().optional(),
});

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ bookId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { bookId } = await params;
  try {
    const body = await request.json();
    const data = updateBookSchema.parse(body);
    await updateBook(session.schoolId, bookId, data);
    return NextResponse.json({ success: true });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to update book' }, { status: 500 });
  }
}

export async function DELETE(_request: NextRequest, { params }: { params: Promise<{ bookId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { bookId } = await params;
  try {
    await deleteBook(session.schoolId, bookId);
    return NextResponse.json({ success: true });
  } catch {
    return NextResponse.json({ error: 'Failed to delete book' }, { status: 500 });
  }
}
