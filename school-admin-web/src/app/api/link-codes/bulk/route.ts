import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { bulkCreateLinkCodes } from '@/lib/firestore/link-codes';
import { z } from 'zod';

const bulkSchema = z.object({
  studentIds: z.array(z.string().min(1)).min(1, 'At least one student required'),
});

export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const body = await request.json();
    const { studentIds } = bulkSchema.parse(body);
    const codes = await bulkCreateLinkCodes(session.schoolId, studentIds, session.uid);
    return NextResponse.json({
      count: codes.length,
      codes: codes.map((c) => ({
        ...c,
        createdAt: c.createdAt.toISOString(),
        expiresAt: c.expiresAt.toISOString(),
      })),
    }, { status: 201 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    const message = error instanceof Error ? error.message : 'Failed to bulk create codes';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
