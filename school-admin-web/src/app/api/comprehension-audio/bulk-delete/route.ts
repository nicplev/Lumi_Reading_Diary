import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import { getSession } from '@/lib/auth/session';
import { bulkDeleteComprehensionAudio } from '@/lib/firestore/comprehensionAudio';

const bodySchema = z.object({
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'startDate must be YYYY-MM-DD'),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'endDate must be YYYY-MM-DD'),
  classId: z.string().min(1).optional(),
});

// POST /api/comprehension-audio/bulk-delete
//
// Deletes all comprehension audio recordings in the caller's school whose
// log `date` falls within the inclusive [startDate, endDate] range, optionally
// scoped to a single class. The reading-log doc itself is preserved.
// Writes one summary entry to adminAuditLog. Per-doc entries would explode
// the audit log on a year-end purge.
export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'School admin role required' }, { status: 403 });
  }

  try {
    const body = await request.json();
    const parsed = bodySchema.parse(body);
    const result = await bulkDeleteComprehensionAudio(
      {
        schoolId: session.schoolId,
        startDate: parsed.startDate,
        endDate: parsed.endDate,
        classId: parsed.classId,
      },
      { uid: session.uid, email: session.email }
    );
    return NextResponse.json(result);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    const message = error instanceof Error ? error.message : 'Failed to bulk delete recordings';
    console.error('bulkDeleteComprehensionAudio failed:', error);
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
