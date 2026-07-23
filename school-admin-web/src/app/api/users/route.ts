import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getUsers, createUser } from '@/lib/firestore/users';
import { isStrongPassword, PASSWORD_REQUIREMENT_TEXT } from '@/lib/utils/password-policy';
import { z } from 'zod';

function serializeUser(u: Record<string, unknown>) {
  return {
    ...u,
    createdAt: u.createdAt instanceof Date ? u.createdAt.toISOString() : u.createdAt,
    lastLoginAt: u.lastLoginAt instanceof Date ? u.lastLoginAt.toISOString() : u.lastLoginAt ?? null,
    tempPasswordCreatedAt:
      u.tempPasswordCreatedAt instanceof Date ? u.tempPasswordCreatedAt.toISOString() : u.tempPasswordCreatedAt ?? null,
  };
}

export async function GET(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  // Staff/parent directory is school-admin only (mirrors /api/parents and the
  // admin-only /users page). Teachers have no directory-listing feature.
  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403 });
  }

  const { searchParams } = new URL(request.url);
  const role = searchParams.get('role') as 'teacher' | 'schoolAdmin' | 'parent' | null;

  try {
    const users = await getUsers(session.schoolId, role ? { role } : undefined);
    return NextResponse.json(users.map((u) => serializeUser(u as unknown as Record<string, unknown>)));
  } catch {
    return NextResponse.json({ error: 'Failed to fetch users' }, { status: 500 });
  }
}

const createUserSchema = z.object({
  email: z.string().email('Valid email is required'),
  fullName: z.string().min(1, 'Name is required'),
  role: z.enum(['teacher', 'schoolAdmin']),
  password: z.string().refine(isStrongPassword, { message: PASSWORD_REQUIREMENT_TEXT }),
});

export async function POST(request: NextRequest) {
  const session = await getSession({ requireMutable: true });
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Only school admins can create users' }, { status: 403 });
  }

  try {
    const body = await request.json();
    const data = createUserSchema.parse(body);
    const id = await createUser(session.schoolId, { ...data, createdBy: session.uid });
    return NextResponse.json({ id }, { status: 201 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    const message = error instanceof Error ? error.message : 'Failed to create user';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
