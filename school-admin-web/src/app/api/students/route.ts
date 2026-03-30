import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getStudents, createStudent } from '@/lib/firestore/students';
import { z } from 'zod';

function serializeStudent(s: Record<string, unknown>) {
  return {
    ...s,
    createdAt: s.createdAt instanceof Date ? s.createdAt.toISOString() : s.createdAt,
    dateOfBirth: s.dateOfBirth instanceof Date ? s.dateOfBirth.toISOString() : s.dateOfBirth ?? null,
    enrolledAt: s.enrolledAt instanceof Date ? s.enrolledAt.toISOString() : s.enrolledAt ?? null,
    readingLevelUpdatedAt: s.readingLevelUpdatedAt instanceof Date ? s.readingLevelUpdatedAt.toISOString() : s.readingLevelUpdatedAt ?? null,
    levelHistory: Array.isArray(s.levelHistory)
      ? (s.levelHistory as Array<Record<string, unknown>>).map((lh) => ({
          ...lh,
          changedAt: lh.changedAt instanceof Date ? lh.changedAt.toISOString() : lh.changedAt,
        }))
      : [],
    stats: s.stats
      ? {
          ...(s.stats as Record<string, unknown>),
          lastReadingDate:
            (s.stats as Record<string, unknown>).lastReadingDate instanceof Date
              ? ((s.stats as Record<string, unknown>).lastReadingDate as Date).toISOString()
              : (s.stats as Record<string, unknown>).lastReadingDate ?? null,
        }
      : null,
  };
}

export async function GET(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { searchParams } = new URL(request.url);
  const classId = searchParams.get('classId') ?? undefined;

  try {
    const students = await getStudents(session.schoolId, { classId });
    return NextResponse.json(students.map((s) => serializeStudent(s as unknown as Record<string, unknown>)));
  } catch {
    return NextResponse.json({ error: 'Failed to fetch students' }, { status: 500 });
  }
}

const createStudentSchema = z.object({
  studentId: z.string().optional(),
  firstName: z.string().min(1, 'First name is required'),
  lastName: z.string().min(1, 'Last name is required'),
  classId: z.string().min(1, 'Class is required'),
  dateOfBirth: z.string().optional(),
  currentReadingLevel: z.string().optional(),
});

export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const body = await request.json();
    const data = createStudentSchema.parse(body);
    const id = await createStudent(session.schoolId, { ...data, createdBy: session.uid });
    return NextResponse.json({ id }, { status: 201 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    if (error instanceof Error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to create student' }, { status: 500 });
  }
}
