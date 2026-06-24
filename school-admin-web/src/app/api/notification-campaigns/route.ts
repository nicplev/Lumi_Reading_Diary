import { NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getNotificationCampaigns } from '@/lib/firestore/notifications';

// History only. Campaign creation goes through the `createNotificationCampaign`
// Cloud Function (callable) so all server-side validation + dispatch + FCM is
// reused — see src/lib/hooks/use-notifications.ts.
export async function GET() {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const campaigns = await getNotificationCampaigns(session.schoolId, {
      createdBy: session.role === 'teacher' ? session.uid : undefined,
    });
    return NextResponse.json(
      campaigns.map((c) => ({
        ...c,
        createdAt: c.createdAt.toISOString(),
        scheduledFor: c.scheduledFor ? c.scheduledFor.toISOString() : null,
        sentAt: c.sentAt ? c.sentAt.toISOString() : null,
      }))
    );
  } catch {
    return NextResponse.json({ error: 'Failed to fetch campaigns' }, { status: 500 });
  }
}
