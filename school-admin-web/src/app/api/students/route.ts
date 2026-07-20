import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getStudents, createStudent } from '@/lib/firestore/students';
import { getClasses } from '@/lib/firestore/classes';
import { teacherTeachesClass } from '@/lib/firestore/comprehensionEvals';
import { z } from 'zod';

function serializeStudent(s: Record<string, unknown>) {
  return {
    ...s,
    createdAt: s.createdAt instanceof Date ? s.createdAt.toISOString() : s.createdAt,
    enrolledAt: s.enrolledAt instanceof Date ? s.enrolledAt.toISOString() : s.enrolledAt ?? null,
    archivedAt: s.archivedAt instanceof Date ? s.archivedAt.toISOString() : s.archivedAt ?? null,
    readingLevelUpdatedAt: s.readingLevelUpdatedAt instanceof Date ? s.readingLevelUpdatedAt.toISOString() : s.readingLevelUpdatedAt ?? null,
    access: s.access
      ? {
          ...(s.access as Record<string, unknown>),
          expiresAt:
            (s.access as Record<string, unknown>).expiresAt instanceof Date
              ? ((s.access as Record<string, unknown>).expiresAt as Date).toISOString()
              : (s.access as Record<string, unknown>).expiresAt ?? null,
          grantedAt:
            (s.access as Record<string, unknown>).grantedAt instanceof Date
              ? ((s.access as Record<string, unknown>).grantedAt as Date).toISOString()
              : (s.access as Record<string, unknown>).grantedAt ?? null,
          revokedAt:
            (s.access as Record<string, unknown>).revokedAt instanceof Date
              ? ((s.access as Record<string, unknown>).revokedAt as Date).toISOString()
              : (s.access as Record<string, unknown>).revokedAt ?? null,
        }
      : null,
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
  // ?status=archived flips the existing isActive filter to the archived side
  // (getStudents defaults to active-only).
  const status = searchParams.get('status');
  const activeFilter = status === 'archived' ? { isActive: false } : {};

  try {
    // Teachers are scoped to the classes they teach; schoolAdmin sees the
    // whole school. A teacher requesting a specific class must teach it; a
    // teacher with no classId gets only their own classes' students (never
    // the whole-school roster).
    if (session.role !== 'schoolAdmin') {
      if (classId) {
        const teaches = await teacherTeachesClass(session.schoolId, classId, session.uid);
        if (!teaches) return NextResponse.json({ error: 'Forbidden' }, { status: 403 });
        const students = await getStudents(session.schoolId, { classId, ...activeFilter });
        return NextResponse.json(
          students.map((s) => serializeStudent(s as unknown as Record<string, unknown>)),
        );
      }
      const myClasses = await getClasses(session.schoolId, { teacherId: session.uid });
      const students = await getStudents(session.schoolId, {
        classIds: myClasses.map((c) => c.id),
        ...activeFilter,
      });
      return NextResponse.json(
        students.map((s) => serializeStudent(s as unknown as Record<string, unknown>)),
      );
    }

    const students = await getStudents(session.schoolId, {
      classId,
      ...activeFilter,
    });
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
  currentReadingLevel: z.string().optional(),
  parentEmail: z
    .string()
    .optional()
    .refine((v) => !v || /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v), 'Invalid parent email'),
});

export async function POST(request: NextRequest) {
  const session = await getSession({ requireMutable: true });
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Only school admins can create students' }, { status: 403 });
  }

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
