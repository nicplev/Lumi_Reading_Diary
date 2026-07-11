import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { assertNotImpersonating } from '@/lib/auth/assert-not-impersonating';
import { z } from 'zod';
import { undoRenewalBatch } from '@/lib/firestore/renewals';

const undoSchema = z.object({ batchId: z.string().min(1) });

// POST /api/renewals/undo — revert a recorded renewal batch (mistake recovery).
export async function POST(request: NextRequest) {
  const session = await getSession({ requireMutable: true });
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Only school admins can undo renewals.' }, { status: 403 });
  }
  const impersonationBlock = assertNotImpersonating(session);
  if (impersonationBlock) return impersonationBlock;

  try {
    const body = await request.json();
    const { batchId } = undoSchema.parse(body);
    const result = await undoRenewalBatch(session.schoolId, batchId, session.uid);
    return NextResponse.json(result);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json(
      { error: error instanceof Error ? error.message : 'Undo failed' },
      { status: 400 }
    );
  }
}
