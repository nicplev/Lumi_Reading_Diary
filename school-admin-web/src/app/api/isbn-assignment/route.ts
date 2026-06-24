import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getStudent } from '@/lib/firestore/students';
import { assignIsbnsToStudentWeek } from '@/lib/firestore/isbn-assignment';
import { z } from 'zod';

const schema = z.object({
  studentId: z.string().min(1),
  isbns: z.array(z.string().trim().min(1)).min(1, 'Enter at least one ISBN').max(50),
  weekStart: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Invalid week'),
});

export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const data = schema.parse(await request.json());

    // classId is taken from the student (server-authoritative), not the client.
    const student = await getStudent(session.schoolId, data.studentId);
    if (!student) return NextResponse.json({ error: 'Student not found' }, { status: 404 });

    const result = await assignIsbnsToStudentWeek(session.schoolId, {
      studentId: data.studentId,
      classId: student.classId ?? '',
      isbns: data.isbns,
      weekStart: data.weekStart,
      actorId: session.uid,
    });
    return NextResponse.json(result);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    if (error instanceof Error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to assign books' }, { status: 500 });
  }
}
