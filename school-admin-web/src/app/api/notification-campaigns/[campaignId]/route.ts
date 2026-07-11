import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { setCampaignArchived } from '@/lib/firestore/notifications';

// Archive / unarchive a message in the Communication history. Ownership is
// enforced in setCampaignArchived (teachers: own; admins: admin-sent).
export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ campaignId: string }> }
) {
  const session = await getSession({ requireMutable: true });
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { campaignId } = await params;
  try {
    const { archived } = await request.json();
    if (typeof archived !== 'boolean') {
      return NextResponse.json({ error: 'archived must be a boolean' }, { status: 400 });
    }
    await setCampaignArchived(session.schoolId, campaignId, archived, {
      uid: session.uid,
      role: session.role,
    });
    return NextResponse.json({ success: true });
  } catch (error) {
    const msg = error instanceof Error ? error.message : 'failed';
    const status = msg === 'forbidden' ? 403 : msg === 'not-found' ? 404 : 500;
    return NextResponse.json({ error: msg }, { status });
  }
}
