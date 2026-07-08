import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { commitRollover } from '@/lib/firestore/rollover';
import { z } from 'zod';

const MAX_ACTIONS = 4000; // rows + missing-student archives, generous headroom

const moveFields = {
  studentDocId: z.string().min(1),
  firstName: z.string().min(1),
  lastName: z.string().min(1),
  className: z.string().min(1),
  yearLevel: z.string().optional(),
  parentEmail: z.string().optional(),
};

const actionSchema = z.discriminatedUnion('action', [
  z.object({ action: z.literal('move'), ...moveFields }),
  z.object({ action: z.literal('backfill_move'), ...moveFields, externalId: z.string().min(1) }),
  z.object({ action: z.literal('restore_move'), ...moveFields }),
  z.object({
    action: z.literal('create'),
    externalId: z.string().optional(),
    firstName: z.string().min(1),
    lastName: z.string().min(1),
    className: z.string().min(1),
    yearLevel: z.string().optional(),
    parentEmail: z
      .string()
      .optional()
      .refine((v) => !v || /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v), 'Invalid parent email'),
    readingLevel: z.string().optional(),
  }),
  z.object({
    action: z.literal('archive'),
    studentDocId: z.string().min(1),
    reason: z.enum(['graduated', 'left']),
  }),
]);

const commitSchema = z.object({
  importId: z.string().uuid('importId must be a UUID'),
  plan: z.object({
    targetAcademicYear: z.number().int().min(2020).max(2100),
    actions: z.array(actionSchema).min(1).max(MAX_ACTIONS),
    classesToDeactivate: z.array(z.string().min(1)).max(200).default([]),
  }),
});

export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Only school admins can run the rollover import' }, { status: 403 });
  }

  try {
    const body = await request.json();
    const { importId, plan } = commitSchema.parse(body);
    const result = await commitRollover(session.schoolId, plan, importId, session.uid, session.fullName);
    return NextResponse.json(result);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    console.error('Rollover commit error:', error);
    const message = error instanceof Error ? error.message : 'Failed to apply the rollover import';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
