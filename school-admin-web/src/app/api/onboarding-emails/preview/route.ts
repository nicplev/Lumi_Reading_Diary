import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { adminDb } from '@/lib/firebase/admin';
import { buildOnboardingEmailPreview } from '@/lib/email-template';
import { z } from 'zod';

const previewSchema = z.object({
  customMessage: z.string().optional(),
});

export async function POST(request: NextRequest) {
  try {
    const session = await getSession();
    if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    const body = await request.json();
    const data = previewSchema.parse(body);

    // Fetch the school name for the template
    const schoolDoc = await adminDb.doc(`schools/${session.schoolId}`).get();
    const schoolName = schoolDoc.exists
      ? (schoolDoc.data()?.name as string) ?? 'Your School'
      : 'Your School';

    const html = buildOnboardingEmailPreview({
      schoolName,
      entries: [
        { studentName: 'Example Student', linkCode: 'ABC123' },
      ],
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
