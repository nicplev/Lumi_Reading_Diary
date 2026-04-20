import { NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getActiveSchoolCode, rotateSchoolCode, type SchoolCode } from '@/lib/firestore/school-codes';
import { getSchool } from '@/lib/firestore/school';

function serialize(code: SchoolCode | null) {
  if (!code) return null;
  return {
    id: code.id,
    code: code.code,
    createdAt: code.createdAt.toISOString(),
    usageCount: code.usageCount,
  };
}

export async function GET() {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const code = await getActiveSchoolCode(session.schoolId);
    return NextResponse.json(serialize(code));
  } catch {
    return NextResponse.json({ error: 'Failed to fetch school code' }, { status: 500 });
  }
}

export async function POST() {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Only school admins can rotate the staff linking code' }, { status: 403 });
  }

  try {
    const school = await getSchool(session.schoolId);
    if (!school) return NextResponse.json({ error: 'School not found' }, { status: 404 });

    const newCode = await rotateSchoolCode(session.schoolId, school.name, session.uid);
    return NextResponse.json(serialize(newCode), { status: 201 });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Failed to rotate school code';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
