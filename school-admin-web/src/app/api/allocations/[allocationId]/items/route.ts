import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { addBookToAllocation, removeBookFromAllocation } from '@/lib/firestore/allocations';
import { z } from 'zod';

const addItemSchema = z.object({
  title: z.string().min(1, 'Title is required'),
  bookId: z.string().optional(),
  isbn: z.string().optional(),
});

export async function POST(request: NextRequest, { params }: { params: Promise<{ allocationId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { allocationId } = await params;
  try {
    const body = await request.json();
    const data = addItemSchema.parse(body);
    await addBookToAllocation(session.schoolId, allocationId, data, session.uid);
    return NextResponse.json({ success: true }, { status: 201 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    const message = error instanceof Error ? error.message : 'Failed to add book';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

const removeItemSchema = z.object({
  itemId: z.string().min(1, 'Item ID is required'),
});

export async function DELETE(request: NextRequest, { params }: { params: Promise<{ allocationId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { allocationId } = await params;
  try {
    const body = await request.json();
    const { itemId } = removeItemSchema.parse(body);
    await removeBookFromAllocation(session.schoolId, allocationId, itemId, session.uid);
    return NextResponse.json({ success: true });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    const message = error instanceof Error ? error.message : 'Failed to remove book';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
