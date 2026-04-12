import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { adminDb } from '@/lib/firebase/admin';
import { z } from 'zod';

const enrollmentSchema = z.object({
  enrollmentStatus: z.enum(['book_pack', 'direct_purchase', 'not_enrolled', 'pending']),
});

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ studentId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

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

    return NextResponse.json({ success: true });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to update enrollment status' }, { status: 500 });
  }
}
