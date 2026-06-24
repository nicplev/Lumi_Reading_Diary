import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getStudentAchievements } from '@/lib/firestore/achievements';

export async function GET(_request: NextRequest, { params }: { params: Promise<{ studentId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { studentId } = await params;
  try {
    const achievements = await getStudentAchievements(session.schoolId, studentId);
    return NextResponse.json(
      achievements.map((a) => ({ ...a, earnedAt: a.earnedAt ? a.earnedAt.toISOString() : null }))
    );
  } catch {
    return NextResponse.json({ error: 'Failed to load achievements' }, { status: 500 });
  }
}
