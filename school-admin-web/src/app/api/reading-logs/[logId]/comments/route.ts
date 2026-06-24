import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import {
  getLogComments,
  addTeacherComment,
  type LogCommentRecord,
} from '@/lib/firestore/reading-logs';
import { z } from 'zod';

function serialize(c: LogCommentRecord) {
  return { ...c, createdAt: c.createdAt ? c.createdAt.toISOString() : null };
}

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ logId: string }> }
) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { logId } = await params;
  try {
    const comments = await getLogComments(session.schoolId, logId);
    return NextResponse.json(comments.map(serialize));
  } catch {
    return NextResponse.json({ error: 'Failed to fetch comments' }, { status: 500 });
  }
}

const postSchema = z.object({
  body: z.string().trim().min(1, 'Comment cannot be empty').max(2000),
});

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ logId: string }> }
) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { logId } = await params;
  try {
    const { body } = postSchema.parse(await request.json());
    const result = await addTeacherComment(session.schoolId, logId, {
      authorId: session.uid,
      authorName: session.fullName,
      body,
    });
    return NextResponse.json(result, { status: 201 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    if (error instanceof Error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to post comment' }, { status: 500 });
  }
}
