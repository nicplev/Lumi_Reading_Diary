import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { updateStudentLevel, getReadingLevelEvents } from '@/lib/firestore/reading-levels';
import { getStudent } from '@/lib/firestore/students';
import { z } from 'zod';

const updateLevelSchema = z.object({
  toLevel: z.string().min(1, 'Level is required'),
  reason: z.string().optional(),
  fromLevel: z.string().optional(),
  fromLevelIndex: z.number().optional(),
  toLevelIndex: z.number().optional(),
});

export async function POST(request: NextRequest, { params }: { params: Promise<{ studentId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { studentId } = await params;
  try {
    const body = await request.json();
    const data = updateLevelSchema.parse(body);

    const student = await getStudent(session.schoolId, studentId);
    if (!student) return NextResponse.json({ error: 'Student not found' }, { status: 404 });

    await updateStudentLevel(session.schoolId, {
      studentId,
      classId: student.classId,
      fromLevel: data.fromLevel ?? student.currentReadingLevel,
      toLevel: data.toLevel,
      fromLevelIndex: data.fromLevelIndex ?? student.currentReadingLevelIndex,
      toLevelIndex: data.toLevelIndex,
      reason: data.reason,
      source: 'web-portal',
      changedByUserId: session.uid,
      changedByRole: session.role,
      changedByName: session.fullName,
    });

    return NextResponse.json({ success: true });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to update level' }, { status: 500 });
  }
}

export async function GET(_request: NextRequest, { params }: { params: Promise<{ studentId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { studentId } = await params;
  try {
    const events = await getReadingLevelEvents(session.schoolId, studentId);
    return NextResponse.json(
      events.map((e) => ({ ...e, createdAt: e.createdAt.toISOString() }))
    );
  } catch {
    return NextResponse.json({ error: 'Failed to fetch level history' }, { status: 500 });
  }
}
