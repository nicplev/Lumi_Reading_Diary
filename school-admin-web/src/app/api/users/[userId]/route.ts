import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getUser, updateUser, deactivateUser, reactivateUser } from '@/lib/firestore/users';
import { z } from 'zod';

export async function GET(_request: NextRequest, { params }: { params: Promise<{ userId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { userId } = await params;
  const user = await getUser(session.schoolId, userId);
  if (!user) return NextResponse.json({ error: 'User not found' }, { status: 404 });

  return NextResponse.json({
    ...user,
    createdAt: user.createdAt.toISOString(),
    lastLoginAt: user.lastLoginAt?.toISOString() ?? null,
  });
}

const updateUserSchema = z.object({
  fullName: z.string().min(1).optional(),
  role: z.enum(['teacher', 'schoolAdmin']).optional(),
  phone: z.string().optional(),
  classIds: z.array(z.string()).optional(),
  reactivate: z.boolean().optional(),
});

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ userId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Only school admins can update users' }, { status: 403 });
  }

  const { userId } = await params;
  try {
    const body = await request.json();
    const data = updateUserSchema.parse(body);

    if (data.reactivate) {
      await reactivateUser(session.schoolId, userId);
    }

    const { reactivate: _, ...updateData } = data;
    if (Object.keys(updateData).length > 0) {
      await updateUser(session.schoolId, userId, updateData);
    }

    return NextResponse.json({ success: true });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to update user' }, { status: 500 });
  }
}

export async function DELETE(_request: NextRequest, { params }: { params: Promise<{ userId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Only school admins can manage users' }, { status: 403 });
  }

  const { userId } = await params;
  try {
    await deactivateUser(session.schoolId, userId);
    return NextResponse.json({ success: true });
  } catch {
    return NextResponse.json({ error: 'Failed to deactivate user' }, { status: 500 });
  }
}
