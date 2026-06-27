import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import {
  getReadingLogsForStudent,
  createTeacherLog,
  type ReadingLogRecord,
} from '@/lib/firestore/reading-logs';
import { z } from 'zod';

function serialize(log: ReadingLogRecord) {
  return {
    ...log,
    date: log.date.toISOString(),
    lastCommentAt: log.lastCommentAt ? log.lastCommentAt.toISOString() : null,
    createdAt: log.createdAt ? log.createdAt.toISOString() : null,
  };
}

export async function GET(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { searchParams } = new URL(request.url);
  const studentId = searchParams.get('studentId');
  if (!studentId) return NextResponse.json({ error: 'studentId is required' }, { status: 400 });

  // Optional date window. Invalid dates are ignored (treated as no bound) — the
  // 2-year hard floor is enforced server-side in getReadingLogsForStudent.
  const parseDate = (raw: string | null): Date | undefined => {
    if (!raw) return undefined;
    const d = new Date(raw);
    return Number.isNaN(d.getTime()) ? undefined : d;
  };
  const from = parseDate(searchParams.get('from'));
  const to = parseDate(searchParams.get('to'));

  try {
    const logs = await getReadingLogsForStudent(session.schoolId, studentId, session.uid, {
      from,
      to,
    });
    return NextResponse.json(logs.map(serialize));
  } catch {
    return NextResponse.json({ error: 'Failed to fetch reading logs' }, { status: 500 });
  }
}

const createLogSchema = z.object({
  studentId: z.string().min(1),
  date: z.string().min(1),
  minutesRead: z.number().int().min(1).max(240),
  bookTitles: z.array(z.string().trim().min(1)).min(1, 'Add at least one book title'),
  notes: z.string().trim().max(280).optional(),
  targetMinutes: z.number().int().min(1).max(240).optional(),
});

export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const data = createLogSchema.parse(await request.json());

    const date = new Date(data.date);
    if (Number.isNaN(date.getTime())) {
      return NextResponse.json({ error: 'Invalid date' }, { status: 400 });
    }
    const now = Date.now();
    if (date.getTime() > now) {
      return NextResponse.json({ error: 'Date cannot be in the future' }, { status: 400 });
    }
    if (date.getTime() < now - 8 * 24 * 60 * 60 * 1000) {
      return NextResponse.json({ error: 'Reading can be backdated up to 7 days' }, { status: 400 });
    }

    const result = await createTeacherLog(session.schoolId, {
      studentId: data.studentId,
      teacherId: session.uid,
      teacherName: session.fullName,
      date,
      minutesRead: data.minutesRead,
      bookTitles: data.bookTitles,
      notes: data.notes,
      targetMinutes: data.targetMinutes,
    });
    return NextResponse.json(result, { status: 201 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    if (error instanceof Error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to create reading log' }, { status: 500 });
  }
}
