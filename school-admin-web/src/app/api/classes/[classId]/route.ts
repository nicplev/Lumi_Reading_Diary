import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getClass, updateClass, deleteClass } from '@/lib/firestore/classes';
import { z } from 'zod';

export async function GET(_request: NextRequest, { params }: { params: Promise<{ classId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { classId } = await params;
  const cls = await getClass(session.schoolId, classId);
  if (!cls) return NextResponse.json({ error: 'Class not found' }, { status: 404 });

  return NextResponse.json({ ...cls, createdAt: cls.createdAt.toISOString() });
}

const updateClassSchema = z.object({
  name: z.string().trim().min(1, 'Class name is required').optional(),
  yearLevel: z.string().optional(),
  teacherIds: z.array(z.string()).optional(),
  defaultMinutesTarget: z.number().min(1).optional(),
});

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ classId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { classId } = await params;
  try {
    const body = await request.json();
    const data = updateClassSchema.parse(body);
    await updateClass(session.schoolId, classId, data);
    return NextResponse.json({ success: true });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to update class' }, { status: 500 });
  }
}

export async function DELETE(_request: NextRequest, { params }: { params: Promise<{ classId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Admin access required' }, { status: 403 });
  }

  const { classId } = await params;
  try {
    await deleteClass(session.schoolId, classId);
    return NextResponse.json({ success: true });
  } catch {
    return NextResponse.json({ error: 'Failed to delete class' }, { status: 500 });
  }
}
