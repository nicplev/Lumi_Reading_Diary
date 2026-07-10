import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getCurrentAcademicYear } from '@/lib/access';
import { previewRollover } from '@/lib/firestore/rollover';
import { z } from 'zod';

// Whole-school files are the point of the rollover import, so the cap is well
// above the legacy import's 500. Rows with missing required fields become
// per-row errors in the preview (not a 400) — the admin sees them in context.
const MAX_ROWS = 2000;

const rowSchema = z.object({
  studentId: z.string().optional(),
  firstName: z.string().default(''),
  lastName: z.string().default(''),
  className: z.string().default(''),
  yearLevel: z.string().optional(),
  parentEmail: z.string().optional(),
  readingLevel: z.string().optional(),
});

const previewSchema = z.object({
  rows: z.array(rowSchema).min(1, 'No rows to preview').max(MAX_ROWS, `Maximum ${MAX_ROWS} rows per import`),
  targetAcademicYear: z.number().int().min(2020).max(2100).optional(),
});

export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Only school admins can run the rollover import' }, { status: 403 });
  }

  try {
    const body = await request.json();
    const data = previewSchema.parse(body);
    const currentAcademicYear = await getCurrentAcademicYear();
    const targetAcademicYear = currentAcademicYear + 1;
    if (data.targetAcademicYear != null && data.targetAcademicYear !== targetAcademicYear) {
      return NextResponse.json(
        { error: `The active school-year transition is ${currentAcademicYear} to ${targetAcademicYear}. Refresh the page and try again.` },
        { status: 409 }
      );
    }
    const preview = await previewRollover(session.schoolId, data.rows, targetAcademicYear);
    return NextResponse.json(preview);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    const message = error instanceof Error ? error.message : 'Failed to preview rollover import';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
