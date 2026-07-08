import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { adminDb } from '@/lib/firebase/admin';
import { z } from 'zod';
import {
  grantStudentAccessForCurrentYear,
  SubscriptionInactiveError,
} from '@/lib/firestore/access-activation';

const enrollmentSchema = z.object({
  enrollmentStatus: z.enum(['book_pack', 'direct_purchase', 'not_enrolled']),
});

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ studentId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Only school admins can update enrollment' }, { status: 403 });
  }

  const { studentId } = await params;
  try {
    const body = await request.json();
    const data = enrollmentSchema.parse(body);

    await adminDb
      .collection('schools')
      .doc(session.schoolId)
      .collection('students')
      .doc(studentId)
      .update({ enrollmentStatus: data.enrollmentStatus });

    // Marking a student subscribed used to write ONLY enrollmentStatus and
    // grant NO access — the footgun where "Subscribed" looked done but the
    // parent still hit the lapsed screen. Now a subscribing status also grants
    // live access for the current year (idempotent; skipped if already live).
    // not_enrolled deliberately never touches access — un-marking isn't a
    // revoke (that stays the subscription cascade's job).
    let accessGranted = false;
    if (data.enrollmentStatus !== 'not_enrolled') {
      const source =
        data.enrollmentStatus === 'direct_purchase' ? 'parent_direct' : 'book_pack_assumed';
      try {
        const res = await grantStudentAccessForCurrentYear(
          session.schoolId,
          studentId,
          session.uid,
          source
        );
        accessGranted = res.granted;
      } catch (err) {
        if (err instanceof SubscriptionInactiveError) {
          // Enrollment status was saved; surface why access wasn't granted so
          // the admin knows to contact Lumi (soft — 200 with a warning).
          return NextResponse.json({
            success: true,
            accessGranted: false,
            warning: err.message,
          });
        }
        throw err;
      }
    }

    return NextResponse.json({ success: true, accessGranted });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to update enrollment status' }, { status: 500 });
  }
}
