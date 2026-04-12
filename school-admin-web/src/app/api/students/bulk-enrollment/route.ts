import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { adminDb } from '@/lib/firebase/admin';
import { z } from 'zod';

const bulkEnrollmentSchema = z.object({
  studentIds: z.array(z.string()).min(1),
  enrollmentStatus: z.enum(['book_pack', 'direct_purchase', 'not_enrolled', 'pending']),
});

export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const body = await request.json();
    const data = bulkEnrollmentSchema.parse(body);

    const studentsRef = adminDb
      .collection('schools')
      .doc(session.schoolId)
      .collection('students');

    const BATCH_SIZE = 400;
    let count = 0;

    for (let i = 0; i < data.studentIds.length; i += BATCH_SIZE) {
      const batch = adminDb.batch();
      const chunk = data.studentIds.slice(i, i + BATCH_SIZE);

      for (const studentId of chunk) {
        batch.update(studentsRef.doc(studentId), {
          enrollmentStatus: data.enrollmentStatus,
        });
      }

      await batch.commit();
      count += chunk.length;
    }

    return NextResponse.json({ count });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to bulk update enrollment status' }, { status: 500 });
  }
}
