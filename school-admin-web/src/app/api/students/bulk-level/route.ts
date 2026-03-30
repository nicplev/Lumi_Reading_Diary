import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { bulkUpdateLevels } from '@/lib/firestore/reading-levels';
import { z } from 'zod';

const bulkLevelSchema = z.object({
  studentIds: z.array(z.string()).min(1),
  toLevel: z.string().min(1),
  toLevelIndex: z.number().optional(),
  reason: z.string().optional(),
});

export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const body = await request.json();
    const data = bulkLevelSchema.parse(body);

    const count = await bulkUpdateLevels(session.schoolId, {
      ...data,
      source: 'web-portal-bulk',
      changedByUserId: session.uid,
      changedByRole: session.role,
      changedByName: session.fullName,
    });

    return NextResponse.json({ count });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to bulk update levels' }, { status: 500 });
  }
}
