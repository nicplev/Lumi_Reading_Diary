import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { revokeLinkCode } from '@/lib/firestore/link-codes';

export async function DELETE(_request: NextRequest, { params }: { params: Promise<{ codeId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { codeId } = await params;
  try {
    await revokeLinkCode(codeId, session.uid);
    return NextResponse.json({ success: true });
  } catch {
    return NextResponse.json({ error: 'Failed to revoke link code' }, { status: 500 });
  }
}
