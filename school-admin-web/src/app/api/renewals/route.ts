import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { assertNotImpersonating } from '@/lib/auth/assert-not-impersonating';
import { z } from 'zod';
import { getCurrentAcademicYear, isRenewalWindowOpen, isSchoolSubActive } from '@/lib/access';
import { getRecentRenewalBatches, getRenewalRoster, renewStudents } from '@/lib/firestore/renewals';

// GET /api/renewals — pre-loaded roster for the next academic year.
export async function GET() {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Only school admins can view renewals' }, { status: 403 });
  }

  try {
    const currentYear = await getCurrentAcademicYear();
    const targetYear = currentYear + 1;
    const [roster, subActive, recentBatches] = await Promise.all([
      getRenewalRoster(session.schoolId, targetYear),
      isSchoolSubActive(session.schoolId, targetYear),
      getRecentRenewalBatches(session.schoolId),
    ]);
    return NextResponse.json({
      currentYear,
      targetYear,
      subActive,
      windowOpen: isRenewalWindowOpen(targetYear),
      recentBatches,
      roster,
    });
  } catch (error) {
    console.error('Renewal roster error:', error);
    return NextResponse.json({ error: 'Failed to load renewal roster' }, { status: 500 });
  }
}

const renewSchema = z.object({
  academicYear: z.number().int().min(2020).max(2100),
  studentIds: z.array(z.string().min(1)).min(1).max(400),
});

// POST /api/renewals — renew the selected students into the target year.
export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Only school admins can renew students' }, { status: 403 });
  }
  const impersonationBlock = assertNotImpersonating(session);
  if (impersonationBlock) return impersonationBlock;

  try {
    const body = await request.json();
    const { academicYear, studentIds } = renewSchema.parse(body);
    const currentAcademicYear = await getCurrentAcademicYear();
    if (academicYear !== currentAcademicYear + 1) {
      return NextResponse.json(
        { error: `The active school-year transition is ${currentAcademicYear} to ${currentAcademicYear + 1}. Refresh the page and try again.` },
        { status: 409 }
      );
    }
    const uniqueStudentIds = Array.from(new Set(studentIds));

    // Fail-closed: a school must both pay AND select. The subscription for the
    // target year must be active before any student can be carried forward.
    if (!(await isSchoolSubActive(session.schoolId, academicYear))) {
      return NextResponse.json(
        { error: 'School subscription is not active for that year. Contact Lumi.' },
        { status: 409 }
      );
    }

    const result = await renewStudents(
      session.schoolId,
      academicYear,
      uniqueStudentIds,
      session.uid,
      session.fullName
    );
    return NextResponse.json(result);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    console.error('Renew students error:', error);
    return NextResponse.json({ error: 'Failed to renew students' }, { status: 500 });
  }
}
