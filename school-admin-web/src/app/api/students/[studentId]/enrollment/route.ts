import { NextRequest, NextResponse } from 'next/server';
import { assertNotImpersonating } from '@/lib/auth/assert-not-impersonating';
import { getSession } from '@/lib/auth/session';
import { z } from 'zod';
import {
  SubscriptionInactiveError,
  updateStudentEnrollmentAndAccess,
} from '@/lib/firestore/access-activation';

const enrollmentSchema = z.object({
  enrollmentStatus: z.enum(['book_pack', 'direct_purchase', 'not_enrolled']),
  reason: z.string().trim().max(250).optional(),
});

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ studentId: string }> }) {
  const session = await getSession({ requireMutable: true });
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Only school admins can update enrollment' }, { status: 403 });
  }
  const impersonationBlock = assertNotImpersonating(session);
  if (impersonationBlock) return impersonationBlock;

  const { studentId } = await params;
  try {
    const body = await request.json();
    const data = enrollmentSchema.parse(body);
    const result = await updateStudentEnrollmentAndAccess(
      session.schoolId,
      [studentId],
      data.enrollmentStatus,
      session.uid,
      data.reason,
    );
    if (result.updated === 0) {
      return NextResponse.json(
        { error: 'Student was not found or is archived.' },
        { status: 409 },
      );
    }
    return NextResponse.json({ success: true, ...result });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    if (error instanceof SubscriptionInactiveError) {
      return NextResponse.json({ error: error.message }, { status: 409 });
    }
    return NextResponse.json({ error: 'Failed to update enrollment and reading access' }, { status: 500 });
  }
}
