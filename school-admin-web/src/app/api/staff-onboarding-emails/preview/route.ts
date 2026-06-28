import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { adminDb } from '@/lib/firebase/admin';
import { getActiveSchoolCode } from '@/lib/firestore/school-codes';
import { buildStaffOnboardingEmailPreview } from '@/lib/staff-email-template';
import { z } from 'zod';

const previewSchema = z.object({
  customMessage: z.string().optional(),
});

export async function POST(request: NextRequest) {
  try {
    const session = await getSession();
    if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    if (session.role !== 'schoolAdmin') {
      return NextResponse.json({ error: 'Only school admins can preview staff emails' }, { status: 403 });
    }

    const body = await request.json();
    const data = previewSchema.parse(body);

    const schoolDoc = await adminDb.doc(`schools/${session.schoolId}`).get();
    const schoolName = schoolDoc.exists
      ? (schoolDoc.data()?.name as string) ?? 'Your School'
      : 'Your School';
    const activeCode = await getActiveSchoolCode(session.schoolId);

    // Preview the admin-created path (the richest case): an example teacher with
    // a temporary password + the school's real join code.
    const html = buildStaffOnboardingEmailPreview({
      schoolName,
      staffName: 'Alex Rivera',
      role: 'teacher',
      loginEmail: 'alex.rivera@example.com',
      tempPassword: 'Kp7-Rm2qXt9',
      schoolCode: activeCode?.code ?? 'ABC12345',
      customMessage: data.customMessage,
    });

    return NextResponse.json({ schoolName, html });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to generate preview' }, { status: 500 });
  }
}
