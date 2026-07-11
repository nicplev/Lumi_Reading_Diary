import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { assertNotImpersonating } from '@/lib/auth/assert-not-impersonating';
import { archiveStudents } from '@/lib/firestore/students';
import { z } from 'zod';

const bulkArchiveSchema = z.object({
  studentIds: z.array(z.string().min(1)).min(1).max(500),
  reason: z.enum(['graduated', 'left', 'manual']).default('manual'),
});

export async function POST(request: NextRequest) {
  const session = await getSession({ requireMutable: true });
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Only school admins can archive students' }, { status: 403 });
  }
  const impersonationBlock = assertNotImpersonating(session);
  if (impersonationBlock) return impersonationBlock;

  try {
    const body = await request.json();
    const data = bulkArchiveSchema.parse(body);
    const count = await archiveStudents(
      session.schoolId,
      Array.from(new Set(data.studentIds)),
      data.reason,
      session.uid
    );
    return NextResponse.json({ count });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    const message = error instanceof Error ? error.message : 'Failed to archive students';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
