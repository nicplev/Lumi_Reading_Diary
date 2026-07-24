import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { lookupBookByIsbn } from '@/lib/firestore/books';
import { consumeRateLimit, RequestGuardError } from '@/lib/http/request-guards';
import { z } from 'zod';

const lookupSchema = z.object({
  // Reject anything that isn't ISBN-shaped (digits/X plus separators) so query
  // injection can't reach the external lookup URLs (finding F-07).
  isbn: z.string().regex(/^[0-9Xx \-]{10,20}$/, 'Enter a valid ISBN'),
});

export async function POST(request: NextRequest) {
  const session = await getSession({ requireMutable: true });
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    // A single lookup can fan out to Google Books + Open Library, so cap
    // per-user lookups to bound external-API cost/abuse (finding F-07).
    await consumeRateLimit(
      'books_lookup',
      [{ key: session.uid, max: 60, windowMs: 60_000 }],
      'Too many book lookups. Please wait a moment and try again.',
    );

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
    if (error instanceof RequestGuardError) {
      return NextResponse.json({ error: error.message }, { status: error.status });
    }
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to lookup ISBN' }, { status: 500 });
  }
}
