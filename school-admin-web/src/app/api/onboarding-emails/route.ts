import { NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { adminDb } from '@/lib/firebase/admin';

function serializeTimestamp(value: unknown): string | null {
  if (!value) return null;
  if (typeof value === 'string') return value;
  if (value instanceof Date) return value.toISOString();
  // Firestore Timestamp
  if (typeof value === 'object' && 'toDate' in (value as Record<string, unknown>)) {
    return (value as { toDate: () => Date }).toDate().toISOString();
  }
  return null;
}

export async function GET() {
  try {
    const session = await getSession();
    if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    const snapshot = await adminDb
      .collection(`schools/${session.schoolId}/parentOnboardingEmails`)
      .orderBy('createdAt', 'desc')
      .limit(50)
      .get();

    const docs = snapshot.docs.map((doc) => {
      const data = doc.data();
      return {
        id: doc.id,
        ...data,
        createdAt: serializeTimestamp(data.createdAt),
        sentAt: serializeTimestamp(data.sentAt),
      };
    });

    return NextResponse.json(docs);
  } catch {
    return NextResponse.json({ error: 'Failed to fetch onboarding emails' }, { status: 500 });
  }
}
