import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { undoRolloverImport, getRecentRolloverImports } from '@/lib/firestore/rollover';
import { z } from 'zod';

// GET /api/rollover/undo — recent imports (for the history / undo list).
export async function GET() {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Only school admins can view rollover imports' }, { status: 403 });
  }

  try {
    const imports = await getRecentRolloverImports(session.schoolId);
    return NextResponse.json({ imports });
  } catch (error) {
    console.error('Rollover imports list error:', error);
    return NextResponse.json({ error: 'Failed to load rollover imports' }, { status: 500 });
  }
}

const undoSchema = z.object({
  importId: z.string().min(1),
});

export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Only school admins can undo a rollover import' }, { status: 403 });
  }

  try {
    const body = await request.json();
    const { importId } = undoSchema.parse(body);
    const result = await undoRolloverImport(session.schoolId, importId, session.uid);
    return NextResponse.json(result);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    console.error('Rollover undo error:', error);
    const message = error instanceof Error ? error.message : 'Failed to undo the rollover import';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
