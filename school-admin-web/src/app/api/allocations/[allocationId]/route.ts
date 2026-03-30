import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getAllocation, updateAllocation, deactivateAllocation } from '@/lib/firestore/allocations';
import { z } from 'zod';

function serializeAllocation(a: Record<string, unknown>) {
  return {
    ...a,
    createdAt: a.createdAt instanceof Date ? a.createdAt.toISOString() : a.createdAt,
    startDate: a.startDate instanceof Date ? a.startDate.toISOString() : a.startDate,
    endDate: a.endDate instanceof Date ? a.endDate.toISOString() : a.endDate,
    assignmentItems: Array.isArray(a.assignmentItems)
      ? (a.assignmentItems as Record<string, unknown>[]).map((item) => ({
          ...item,
          addedAt: item.addedAt instanceof Date ? item.addedAt.toISOString() : item.addedAt ?? null,
        }))
      : [],
  };
}

export async function GET(_request: NextRequest, { params }: { params: Promise<{ allocationId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { allocationId } = await params;
  const allocation = await getAllocation(session.schoolId, allocationId);
  if (!allocation) return NextResponse.json({ error: 'Allocation not found' }, { status: 404 });

  return NextResponse.json(serializeAllocation(allocation as unknown as Record<string, unknown>));
}

const updateAllocationSchema = z.object({
  cadence: z.enum(['daily', 'weekly', 'fortnightly', 'custom']).optional(),
  targetMinutes: z.number().min(1).optional(),
  type: z.enum(['byLevel', 'byTitle', 'freeChoice']).optional(),
  levelStart: z.string().optional(),
  levelEnd: z.string().optional(),
  startDate: z.string().optional(),
  endDate: z.string().optional(),
  studentIds: z.array(z.string()).optional(),
});

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ allocationId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { allocationId } = await params;
  try {
    const body = await request.json();
    const data = updateAllocationSchema.parse(body);
    await updateAllocation(session.schoolId, allocationId, { ...data, updatedBy: session.uid });
    return NextResponse.json({ success: true });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to update allocation' }, { status: 500 });
  }
}

export async function DELETE(_request: NextRequest, { params }: { params: Promise<{ allocationId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { allocationId } = await params;
  try {
    await deactivateAllocation(session.schoolId, allocationId);
    return NextResponse.json({ success: true });
  } catch {
    return NextResponse.json({ error: 'Failed to deactivate allocation' }, { status: 500 });
  }
}
