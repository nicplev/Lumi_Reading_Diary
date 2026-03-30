import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { lookupBookByIsbn } from '@/lib/firestore/books';
import { z } from 'zod';

const lookupSchema = z.object({
  isbn: z.string().min(1, 'ISBN is required'),
});

export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const body = await request.json();
    const { isbn } = lookupSchema.parse(body);
    const book = await lookupBookByIsbn(isbn, session.schoolId, session.uid);

    if (!book) {
      return NextResponse.json({ book: null });
    }

    return NextResponse.json({
      book: {
        ...book,
        createdAt: book.createdAt.toISOString(),
        publishedDate: book.publishedDate?.toISOString() ?? null,
      },
    });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to lookup ISBN' }, { status: 500 });
  }
}
