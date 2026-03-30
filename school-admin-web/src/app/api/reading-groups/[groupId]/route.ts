import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { updateReadingGroup, deleteReadingGroup, assignStudentsToGroup } from '@/lib/firestore/reading-groups';
import { z } from 'zod';

const updateGroupSchema = z.object({
  name: z.string().min(1).optional(),
  readingLevel: z.string().optional(),
  color: z.string().optional(),
  description: z.string().optional(),
  targetMinutes: z.number().optional(),
  studentIds: z.array(z.string()).optional(),
});

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ groupId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { groupId } = await params;
  try {
    const body = await request.json();
    const data = updateGroupSchema.parse(body);

    // If studentIds are being updated, use the dedicated function
    if (data.studentIds) {
      await assignStudentsToGroup(session.schoolId, groupId, data.studentIds);
    }

    // Update other fields
    const { studentIds: _, ...updateData } = data;
    if (Object.keys(updateData).length > 0) {
      await updateReadingGroup(session.schoolId, groupId, updateData);
    }

    return NextResponse.json({ success: true });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to update reading group' }, { status: 500 });
  }
}

export async function DELETE(_request: NextRequest, { params }: { params: Promise<{ groupId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { groupId } = await params;
  try {
    await deleteReadingGroup(session.schoolId, groupId);
    return NextResponse.json({ success: true });
  } catch {
    return NextResponse.json({ error: 'Failed to delete reading group' }, { status: 500 });
  }
}
