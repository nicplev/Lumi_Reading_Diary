import { NextRequest, NextResponse } from 'next/server';
import { getSession, createSessionCookie } from '@/lib/auth/session';
import { getUser, updateUser } from '@/lib/firestore/users';

export async function GET() {
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: 'Not authenticated' }, { status: 401 });
  }

  const user = await getUser(session.schoolId, session.uid);
  if (!user) {
    return NextResponse.json({ error: 'User not found' }, { status: 404 });
  }

  return NextResponse.json(user);
}

export async function PATCH(request: NextRequest) {
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: 'Not authenticated' }, { status: 401 });
  }

  const body = await request.json();
  const { fullName, phone } = body;

  const update: { fullName?: string; phone?: string } = {};
  if (typeof fullName === 'string' && fullName.trim()) {
    update.fullName = fullName.trim();
  }
  if (typeof phone === 'string') {
    update.phone = phone.trim();
  }

  if (Object.keys(update).length === 0) {
    return NextResponse.json({ error: 'No valid fields to update' }, { status: 400 });
  }

  await updateUser(session.schoolId, session.uid, update);

  // Update the session cookie so sidebar reflects changes immediately
  if (update.fullName) {
    await createSessionCookie({ ...session, fullName: update.fullName });
  }

  return NextResponse.json({ success: true });
}
