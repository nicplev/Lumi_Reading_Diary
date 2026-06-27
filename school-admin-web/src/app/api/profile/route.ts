import { NextRequest, NextResponse } from 'next/server';
import { getSession, createSessionCookie } from '@/lib/auth/session';
import { getUser, updateUser } from '@/lib/firestore/users';
import { isStaffCharacterAllowed } from '@/lib/staff-characters';

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
  const { fullName, phone, characterId } = body;

  const update: { fullName?: string; phone?: string; characterId?: string } = {};
  if (typeof fullName === 'string' && fullName.trim()) {
    update.fullName = fullName.trim();
  }
  if (typeof phone === 'string') {
    update.phone = phone.trim();
  }
  if (typeof characterId === 'string') {
    // A teacher may only pick mt_*/ft_*, an admin only la_* (slug category = role).
    if (!isStaffCharacterAllowed(session.role, characterId)) {
      return NextResponse.json({ error: 'That character is not available for your role.' }, { status: 400 });
    }
    update.characterId = characterId;
  }

  if (Object.keys(update).length === 0) {
    return NextResponse.json({ error: 'No valid fields to update' }, { status: 400 });
  }

  await updateUser(session.schoolId, session.uid, update);

  // Re-issue the session cookie so the profile chip reflects changes immediately.
  if (update.fullName || update.characterId) {
    await createSessionCookie({
      ...session,
      fullName: update.fullName ?? session.fullName,
      characterId: update.characterId ?? session.characterId,
    });
  }

  return NextResponse.json({ success: true });
}
