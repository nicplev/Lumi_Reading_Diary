import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { previewComprehensionAudioCount } from '@/lib/firestore/comprehensionAudio';

// GET /api/comprehension-audio/preview-count?startDate=YYYY-MM-DD&endDate=YYYY-MM-DD[&classId=...]
//
// Returns how many comprehension recordings in the school match the filter
// without deleting anything. Scoped to the caller's school via the session
// cookie — the client cannot target another school.
export async function GET(request: NextRequest) {
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'School admin role required' }, { status: 403 });
  }

  const params = request.nextUrl.searchParams;
  const startDate = params.get('startDate') ?? '';
  const endDate = params.get('endDate') ?? '';
  const classId = params.get('classId') ?? undefined;

  try {
    const result = await previewComprehensionAudioCount({
      schoolId: session.schoolId,
      startDate,
      endDate,
      classId: classId || undefined,
    });
    return NextResponse.json(result);
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Failed to preview count';
    return NextResponse.json({ error: message }, { status: 400 });
  }
}
