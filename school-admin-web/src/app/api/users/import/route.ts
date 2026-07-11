import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { importStaff } from '@/lib/firestore/users';
import { adminDb } from '@/lib/firebase/admin';
import { z } from 'zod';

const rowSchema = z.object({
  fullName: z.string(),
  email: z.string(),
  role: z.string().optional().default(''),
});

const importSchema = z.object({
  rows: z.array(rowSchema).min(1, 'At least one row is required').max(500, 'Import at most 500 staff at a time'),
  customMessage: z.string().max(2000).optional(),
});

export async function POST(request: NextRequest) {
  const session = await getSession({ requireMutable: true });
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Only school admins can import staff' }, { status: 403 });
  }

  try {
    const body = await request.json();
    const { rows, customMessage } = importSchema.parse(body);

    const result = await importStaff(session.schoolId, rows, session.uid);

    // Queue login emails for the accounts we just created.
    if (result.created.length > 0) {
      await adminDb
        .collection(`schools/${session.schoolId}/staffOnboardingEmails`)
        .add({
          status: 'queued',
          schoolId: session.schoolId,
          createdAt: new Date(),
          createdBy: session.uid,
          targetUserIds: result.created.map((c) => c.uid),
          customMessage: customMessage ?? null,
        });
    }

    return NextResponse.json(result);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to import staff' }, { status: 500 });
  }
}
