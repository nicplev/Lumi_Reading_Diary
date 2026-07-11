import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { adminDb } from '@/lib/firebase/admin';
import { z } from 'zod';

const sendSchema = z.object({
  targetUserIds: z.array(z.string()).min(1),
  emailSubject: z.string().max(200).optional(),
  customMessage: z.string().max(2000).optional(),
});

export async function POST(request: NextRequest) {
  const session = await getSession({ requireMutable: true });
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Only school admins can send staff emails' }, { status: 403 });
  }

  try {
    const body = await request.json();
    const data = sendSchema.parse(body);

    const docRef = await adminDb
      .collection(`schools/${session.schoolId}/staffOnboardingEmails`)
      .add({
        status: 'queued',
        schoolId: session.schoolId,
        createdAt: new Date(),
        createdBy: session.uid,
        targetUserIds: data.targetUserIds,
        emailSubject: data.emailSubject ?? null,
        customMessage: data.customMessage ?? null,
      });

    return NextResponse.json({ id: docRef.id, status: 'queued' }, { status: 201 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to queue staff emails' }, { status: 500 });
  }
}
