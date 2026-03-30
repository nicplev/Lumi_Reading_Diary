import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getClasses, createClass } from '@/lib/firestore/classes';
import { z } from 'zod';

export async function GET() {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const classes = await getClasses(session.schoolId, {
      teacherId: session.role === 'teacher' ? session.uid : undefined,
    });
    return NextResponse.json(classes.map((c) => ({ ...c, createdAt: c.createdAt.toISOString() })));
  } catch (error) {
    return NextResponse.json({ error: 'Failed to fetch classes' }, { status: 500 });
  }
}

const createClassSchema = z.object({
  name: z.string().min(1, 'Name is required'),
  yearLevel: z.string().optional(),
  teacherIds: z.array(z.string()).default([]),
  defaultMinutesTarget: z.number().min(1).default(15),
});

export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const body = await request.json();
    const data = createClassSchema.parse(body);
    const id = await createClass(session.schoolId, { ...data, createdBy: session.uid });
    return NextResponse.json({ id }, { status: 201 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to create class' }, { status: 500 });
  }
}
