import { NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { adminDb } from '@/lib/firebase/admin';

// DELETE /api/onboarding-emails/[id] — remove a single email-history receipt.
// schoolAdmin only. Only the record is deleted; the email itself is untouched.
export async function DELETE(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const session = await getSession({ requireMutable: true });
    if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    if (session.role !== 'schoolAdmin') {
      return NextResponse.json({ error: 'Forbidden' }, { status: 403 });
    }

    const { id } = await params;
    await adminDb
      .doc(`schools/${session.schoolId}/parentOnboardingEmails/${id}`)
      .delete();

    return NextResponse.json({ success: true });
  } catch {
    return NextResponse.json(
      { error: 'Failed to delete onboarding email' },
      { status: 500 }
    );
  }
}
