import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { importStudents, type CSVRow } from '@/lib/firestore/students';
import { z } from 'zod';

// Field-length caps bound what a single import can store: the row cap alone
// still allowed 500 rows of arbitrarily long strings. Mirrors the rollover
// routes — keep the three in sync.
const rowSchema = z.object({
  studentId: z.string().max(64).optional(),
  firstName: z.string().min(1).max(100),
  lastName: z.string().min(1).max(100),
  className: z.string().min(1).max(100),
  yearLevel: z.string().max(32).optional(),
  // Same format guard as the rollover commit route: this value is stored as
  // additionalInfo.pendingParentEmail and later used as an email recipient.
  parentEmail: z
    .string()
    .max(254)
    .optional()
    .refine((v) => !v || /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v), 'Invalid parent email'),
  readingLevel: z.string().max(64).optional(),
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
