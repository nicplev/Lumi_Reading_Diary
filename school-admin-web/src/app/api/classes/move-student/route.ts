import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { moveStudentToClass } from '@/lib/firestore/students';
import { z } from 'zod';

const moveSchema = z.object({
  studentId: z.string().min(1),
  fromClassId: z.string().nullable(),
  toClassId: z.string().nullable(),
});

export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const body = await request.json();
    const data = moveSchema.parse(body);

    await moveStudentToClass(
      session.schoolId,
      data.studentId,
      data.fromClassId,
      data.toClassId,
    );

    return NextResponse.json({ success: true });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to move student' }, { status: 500 });
  }
}
