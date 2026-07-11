import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import {
  getComprehensionQuestion,
  setComprehensionQuestion,
  DEFAULT_COMPREHENSION_QUESTION,
} from '@/lib/firestore/comprehension';
import { z } from 'zod';

export async function GET(_request: NextRequest, { params }: { params: Promise<{ classId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { classId } = await params;
  try {
    const question = await getComprehensionQuestion(session.schoolId, classId);
    return NextResponse.json({ question, default: DEFAULT_COMPREHENSION_QUESTION });
  } catch {
    return NextResponse.json({ error: 'Failed to load comprehension question' }, { status: 500 });
  }
}

const schema = z.object({ question: z.string().max(200, 'Keep it under 200 characters') });

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ classId: string }> }) {
  const session = await getSession({ requireMutable: true });
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { classId } = await params;
  try {
    const { question } = schema.parse(await request.json());
    const saved = await setComprehensionQuestion(session.schoolId, classId, question);
    return NextResponse.json({ question: saved, default: DEFAULT_COMPREHENSION_QUESTION });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to save comprehension question' }, { status: 500 });
  }
}
