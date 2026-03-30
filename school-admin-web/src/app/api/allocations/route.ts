import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getAllocations, createAllocation } from '@/lib/firestore/allocations';
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
    studentOverrides: a.studentOverrides
      ? Object.fromEntries(
          Object.entries(a.studentOverrides as Record<string, Record<string, unknown>>).map(([k, v]) => [
            k,
            {
              ...v,
              updatedAt: v.updatedAt instanceof Date ? v.updatedAt.toISOString() : v.updatedAt ?? null,
              addedItems: Array.isArray(v.addedItems)
                ? (v.addedItems as Record<string, unknown>[]).map((item) => ({
                    ...item,
                    addedAt: item.addedAt instanceof Date ? item.addedAt.toISOString() : item.addedAt ?? null,
                  }))
                : [],
            },
          ])
        )
      : {},
  };
}

export async function GET(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { searchParams } = new URL(request.url);
  const classId = searchParams.get('classId') ?? undefined;
  const isActiveParam = searchParams.get('isActive');
  const isActive = isActiveParam === 'true' ? true : isActiveParam === 'false' ? false : undefined;

  try {
    const allocations = await getAllocations(session.schoolId, { classId, isActive });
    return NextResponse.json(allocations.map((a) => serializeAllocation(a as unknown as Record<string, unknown>)));
  } catch {
    return NextResponse.json({ error: 'Failed to fetch allocations' }, { status: 500 });
  }
}

const createAllocationSchema = z.object({
  classId: z.string().min(1, 'Class is required'),
  type: z.enum(['byLevel', 'byTitle', 'freeChoice']),
  cadence: z.enum(['daily', 'weekly', 'fortnightly', 'custom']),
  targetMinutes: z.number().min(1).default(15),
  startDate: z.string().min(1, 'Start date is required'),
  endDate: z.string().min(1, 'End date is required'),
  levelStart: z.string().optional(),
  levelEnd: z.string().optional(),
  studentIds: z.array(z.string()).default([]),
  assignmentItems: z.array(z.object({
    title: z.string().min(1),
    bookId: z.string().optional(),
    isbn: z.string().optional(),
  })).default([]),
});

export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const body = await request.json();
    const data = createAllocationSchema.parse(body);
    const id = await createAllocation(session.schoolId, {
      ...data,
      teacherId: session.uid,
      createdBy: session.uid,
    });
    return NextResponse.json({ id }, { status: 201 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to create allocation' }, { status: 500 });
  }
}
