import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { reorderReadingGroups } from '@/lib/firestore/reading-groups';
import { z } from 'zod';

const reorderSchema = z.object({
  classId: z.string().min(1),
  orderedIds: z.array(z.string()).min(1),
});

export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const body = await request.json();
    const { orderedIds } = reorderSchema.parse(body);
    await reorderReadingGroups(session.schoolId, orderedIds);
    return NextResponse.json({ success: true });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to reorder reading groups' }, { status: 500 });
  }
}
