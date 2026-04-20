import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getStudent, updateStudent, deleteStudent } from '@/lib/firestore/students';
import { z } from 'zod';

export async function GET(_request: NextRequest, { params }: { params: Promise<{ studentId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { studentId } = await params;
  const student = await getStudent(session.schoolId, studentId);
  if (!student) return NextResponse.json({ error: 'Student not found' }, { status: 404 });

  return NextResponse.json({
    ...student,
    createdAt: student.createdAt.toISOString(),
    dateOfBirth: student.dateOfBirth?.toISOString() ?? null,
    enrolledAt: student.enrolledAt?.toISOString() ?? null,
    readingLevelUpdatedAt: student.readingLevelUpdatedAt?.toISOString() ?? null,
    levelHistory: student.levelHistory.map((lh) => ({
      ...lh,
      changedAt: lh.changedAt.toISOString(),
    })),
    stats: student.stats
      ? { ...student.stats, lastReadingDate: student.stats.lastReadingDate?.toISOString() ?? null }
      : null,
  });
}

const updateStudentSchema = z.object({
  firstName: z.string().min(1).optional(),
  lastName: z.string().min(1).optional(),
  studentId: z.string().optional(),
  classId: z.string().optional(),
  currentReadingLevel: z.string().optional(),
  parentEmail: z
    .string()
    .optional()
    .refine((v) => v === undefined || v === '' || /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v), 'Invalid parent email'),
});

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ studentId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { studentId } = await params;
  try {
    const body = await request.json();
    const data = updateStudentSchema.parse(body);
    await updateStudent(session.schoolId, studentId, data);
    return NextResponse.json({ success: true });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to update student' }, { status: 500 });
  }
}

export async function DELETE(_request: NextRequest, { params }: { params: Promise<{ studentId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { studentId } = await params;
  try {
    await deleteStudent(session.schoolId, studentId);
    return NextResponse.json({ success: true });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Failed to delete student';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
