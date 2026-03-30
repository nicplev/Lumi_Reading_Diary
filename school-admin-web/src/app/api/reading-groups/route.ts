import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getReadingGroups, createReadingGroup } from '@/lib/firestore/reading-groups';
import { z } from 'zod';

export async function GET(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { searchParams } = new URL(request.url);
  const classId = searchParams.get('classId');
  if (!classId) return NextResponse.json({ error: 'classId is required' }, { status: 400 });

  try {
    const groups = await getReadingGroups(session.schoolId, classId);
    return NextResponse.json(groups.map((g) => ({ ...g, createdAt: g.createdAt.toISOString() })));
  } catch {
    return NextResponse.json({ error: 'Failed to fetch reading groups' }, { status: 500 });
  }
}

const createGroupSchema = z.object({
  name: z.string().min(1, 'Name is required'),
  classId: z.string().min(1),
  readingLevel: z.string().optional(),
  color: z.string().optional(),
  description: z.string().optional(),
  targetMinutes: z.number().optional(),
});

export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const body = await request.json();
    const data = createGroupSchema.parse(body);
    const id = await createReadingGroup(session.schoolId, {
      ...data,
      teacherId: session.uid,
    });
    return NextResponse.json({ id }, { status: 201 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to create reading group' }, { status: 500 });
  }
}
