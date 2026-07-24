import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { importStudents, type CSVRow } from '@/lib/firestore/students';
import { z } from 'zod';

const rowSchema = z.object({
  studentId: z.string().optional(),
  firstName: z.string().min(1),
  lastName: z.string().min(1),
  className: z.string().min(1),
  yearLevel: z.string().optional(),
  parentEmail: z.string().optional(),
  readingLevel: z.string().optional(),
});

const importSchema = z.object({
  rows: z
    .array(rowSchema)
    .min(1, 'At least one row is required')
    .max(500, 'Import at most 500 students at a time'),
});

export async function POST(request: NextRequest) {
  const session = await getSession({ requireMutable: true });
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Only school admins can import students' }, { status: 403 });
  }

  try {
    const body = await request.json();
    const { rows } = importSchema.parse(body);
    const result = await importStudents(session.schoolId, rows as CSVRow[], session.uid);
    return NextResponse.json(result);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to import students' }, { status: 500 });
  }
}
