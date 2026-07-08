import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { restoreStudents } from '@/lib/firestore/students';
import { z } from 'zod';

const restoreSchema = z.object({
  studentIds: z.array(z.string()).min(1),
});

export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Only school admins can restore students' }, { status: 403 });
  }

  try {
    const body = await request.json();
    const data = restoreSchema.parse(body);
    const result = await restoreStudents(session.schoolId, data.studentIds);
    return NextResponse.json(result);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    const message = error instanceof Error ? error.message : 'Failed to restore students';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
