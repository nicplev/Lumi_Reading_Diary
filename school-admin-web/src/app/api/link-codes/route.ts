import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getLinkCodes, createLinkCode } from '@/lib/firestore/link-codes';
import { z } from 'zod';

function serializeLinkCode(lc: Record<string, unknown>) {
  return {
    ...lc,
    createdAt: lc.createdAt instanceof Date ? lc.createdAt.toISOString() : lc.createdAt,
    expiresAt: lc.expiresAt instanceof Date ? lc.expiresAt.toISOString() : lc.expiresAt,
    usedAt: lc.usedAt instanceof Date ? lc.usedAt.toISOString() : lc.usedAt ?? null,
  };
}

export async function GET() {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const codes = await getLinkCodes(session.schoolId);
    return NextResponse.json(codes.map((c) => serializeLinkCode(c as unknown as Record<string, unknown>)));
  } catch {
    return NextResponse.json({ error: 'Failed to fetch link codes' }, { status: 500 });
  }
}

const createSchema = z.object({
  studentId: z.string().min(1, 'Student is required'),
});

export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const body = await request.json();
    const { studentId } = createSchema.parse(body);
    const code = await createLinkCode(session.schoolId, studentId, session.uid);
    return NextResponse.json(serializeLinkCode(code as unknown as Record<string, unknown>), { status: 201 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    const message = error instanceof Error ? error.message : 'Failed to create link code';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
