import { NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getIncompleteBooks } from '@/lib/firestore/books';

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
    const books = await getIncompleteBooks(session.schoolId);
    return NextResponse.json(books.map((b) => serializeBook(b as unknown as Record<string, unknown>)));
  } catch {
    return NextResponse.json({ error: 'Failed to fetch incomplete books' }, { status: 500 });
  }
}
