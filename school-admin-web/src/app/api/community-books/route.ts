import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { upsertCommunityBook } from '@/lib/firestore/community-books';
import { z } from 'zod';

const MAX_COVER_BYTES = 3_000_000; // ~3MB; client resizes to ~600x800 first

const schema = z.object({
  isbn: z.string().min(1),
  title: z.string().trim().min(1, 'Title is required'),
  author: z.string().trim().max(300).optional(),
  readingLevel: z.string().trim().max(100).optional(),
  description: z.string().trim().max(4000).optional(),
  coverDataUrl: z.string().optional(),
});

export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const data = schema.parse(await request.json());

    let coverBuffer: Buffer | undefined;
    if (data.coverDataUrl) {
      const match = /^data:image\/\w+;base64,(.+)$/.exec(data.coverDataUrl);
      if (!match) return NextResponse.json({ error: 'Invalid cover image' }, { status: 400 });
      coverBuffer = Buffer.from(match[1], 'base64');
      if (coverBuffer.length > MAX_COVER_BYTES) {
        return NextResponse.json({ error: 'Cover image is too large' }, { status: 400 });
      }
    }

    const result = await upsertCommunityBook({
      isbn: data.isbn,
      title: data.title,
      author: data.author,
      readingLevel: data.readingLevel,
      description: data.description,
      coverBuffer,
      contributedBy: session.uid,
      contributedBySchoolId: session.schoolId,
      contributedByName: session.fullName,
    });
    return NextResponse.json(result, { status: result.created ? 201 : 200 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    if (error instanceof Error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to contribute book' }, { status: 500 });
  }
}
