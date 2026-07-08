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

// DELETE /api/onboarding-emails?olderThanDays=30 — cull old receipts. Only the
// history records are removed; nothing is re-sent or recalled. schoolAdmin only.
export async function DELETE(request: Request) {
  try {
    const session = await getSession();
    if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    if (session.role !== 'schoolAdmin') {
      return NextResponse.json({ error: 'Forbidden' }, { status: 403 });
    }

    const olderThanDays = Number(
      new URL(request.url).searchParams.get('olderThanDays')
    );
    if (!Number.isFinite(olderThanDays) || olderThanDays < 0) {
      return NextResponse.json(
        { error: 'olderThanDays must be a non-negative number' },
        { status: 400 }
      );
    }

    const cutoff = new Date(Date.now() - olderThanDays * 24 * 60 * 60 * 1000);
    const snapshot = await adminDb
      .collection(`schools/${session.schoolId}/parentOnboardingEmails`)
      .where('createdAt', '<', cutoff)
      .get();

    let deleted = 0;
    const docs = snapshot.docs;
    // Firestore commits at most 500 writes per batch.
    for (let i = 0; i < docs.length; i += 400) {
      const chunk = docs.slice(i, i + 400);
      const batch = adminDb.batch();
      for (const d of chunk) batch.delete(d.ref);
      await batch.commit();
      deleted += chunk.length;
    }

    return NextResponse.json({ deleted });
  } catch {
    return NextResponse.json({ error: 'Failed to cull onboarding emails' }, { status: 500 });
  }
}
