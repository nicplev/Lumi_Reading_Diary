import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { adminDb } from '@/lib/firebase/admin';
import { z } from 'zod';

const sendSchema = z.object({
  targetStudentIds: z.array(z.string()).min(1),
  emailSubject: z.string().optional(),
  customMessage: z.string().optional(),
  generateMissingCodes: z.boolean().default(true),
});

export async function POST(request: NextRequest) {
  try {
    const session = await getSession();
    if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    const body = await request.json();
    const data = sendSchema.parse(body);

    const docRef = await adminDb
      .collection(`schools/${session.schoolId}/parentOnboardingEmails`)
      .add({
        status: 'queued',
        schoolId: session.schoolId,
        createdAt: new Date(),
        createdBy: session.uid,
        targetStudentIds: data.targetStudentIds,
        emailSubject: data.emailSubject ?? null,
        customMessage: data.customMessage ?? null,
        generateMissingCodes: data.generateMissingCodes,
      });

    return NextResponse.json({ id: docRef.id, status: 'queued' }, { status: 201 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to queue onboarding emails' }, { status: 500 });
  }
}
