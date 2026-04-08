import { NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getParentsWithStudents } from '@/lib/firestore/parents';

function serializeParent(p: Record<string, unknown>) {
  return {
    ...p,
    createdAt: p.createdAt instanceof Date ? p.createdAt.toISOString() : p.createdAt,
    lastLoginAt: p.lastLoginAt instanceof Date ? p.lastLoginAt.toISOString() : p.lastLoginAt ?? null,
  };
}

export async function GET() {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const parents = await getParentsWithStudents(session.schoolId);
    return NextResponse.json(parents.map((p) => serializeParent(p as unknown as Record<string, unknown>)));
  } catch {
    return NextResponse.json({ error: 'Failed to fetch parents' }, { status: 500 });
  }
}
