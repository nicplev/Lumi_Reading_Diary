import { NextRequest, NextResponse } from 'next/server';
import { assertNotImpersonating } from '@/lib/auth/assert-not-impersonating';
import { getSession } from '@/lib/auth/session';
import { z } from 'zod';
import {
  SubscriptionInactiveError,
  updateStudentEnrollmentAndAccess,
} from '@/lib/firestore/access-activation';

const bulkEnrollmentSchema = z.object({
  studentIds: z.array(z.string().trim().min(1).max(256)).min(1).max(400),
  enrollmentStatus: z.enum(['book_pack', 'direct_purchase', 'not_enrolled']),
  reason: z.string().trim().max(250).optional(),
});

export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Only school admins can update enrollment' }, { status: 403 });
  }
  const impersonationBlock = assertNotImpersonating(session);
  if (impersonationBlock) return impersonationBlock;

  try {
    const body = await request.json();
    const data = bulkEnrollmentSchema.parse(body);
    const result = await updateStudentEnrollmentAndAccess(
      session.schoolId,
      data.studentIds,
      data.enrollmentStatus,
      session.uid,
      data.reason,
    );
    return NextResponse.json({ count: result.updated, ...result });
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
