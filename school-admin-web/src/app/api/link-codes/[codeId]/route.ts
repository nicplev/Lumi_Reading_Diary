import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { revokeLinkCode, deleteLinkCode } from '@/lib/firestore/link-codes';

export async function DELETE(request: NextRequest, { params }: { params: Promise<{ codeId: string }> }) {
  const session = await getSession({ requireMutable: true });
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Only school admins can manage link codes' }, { status: 403 });
  }

  const { codeId } = await params;
  const permanent = request.nextUrl.searchParams.get('permanent') === 'true';

  try {
    if (permanent) {
      await deleteLinkCode(codeId, session.schoolId);
    } else {
      await revokeLinkCode(codeId, session.uid, session.schoolId);
    }
    return NextResponse.json({ success: true });
  } catch (e) {
    return NextResponse.json({ error: e instanceof Error ? e.message : 'Failed' }, { status: 500 });
  }
}
