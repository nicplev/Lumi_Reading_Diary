import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { z } from 'zod';
import { getCurrentAcademicYear, isSchoolSubActive } from '@/lib/access';
import { getRenewalRoster, renewStudents } from '@/lib/firestore/renewals';

// GET /api/renewals — pre-loaded roster for the next academic year.
export async function GET() {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const currentYear = await getCurrentAcademicYear();
    const targetYear = currentYear + 1;
    const [roster, subActive] = await Promise.all([
      getRenewalRoster(session.schoolId, targetYear),
      isSchoolSubActive(session.schoolId, targetYear),
    ]);
    return NextResponse.json({ currentYear, targetYear, subActive, roster });
  } catch (error) {
    console.error('Renewal roster error:', error);
    return NextResponse.json({ error: 'Failed to load renewal roster' }, { status: 500 });
  }
}

const renewSchema = z.object({
  academicYear: z.number().int().min(2020).max(2100),
  studentIds: z.array(z.string().min(1)).min(1),
});

// POST /api/renewals — renew the selected students into the target year.
export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const body = await request.json();
    const { academicYear, studentIds } = renewSchema.parse(body);

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
      studentIds,
      session.uid
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
