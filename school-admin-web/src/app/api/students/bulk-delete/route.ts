import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { deleteStudents } from '@/lib/firestore/students';
import { z } from 'zod';

const bulkDeleteSchema = z.object({
  studentIds: z.array(z.string()).min(1),
});

export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const body = await request.json();
    const data = bulkDeleteSchema.parse(body);
    const count = await deleteStudents(session.schoolId, data.studentIds);
    return NextResponse.json({ count });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    const message = error instanceof Error ? error.message : 'Failed to bulk delete students';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
