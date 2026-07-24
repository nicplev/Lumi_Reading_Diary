import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { assertNotImpersonating } from '@/lib/auth/assert-not-impersonating';
import { getCurrentAcademicYear } from '@/lib/access';
import { commitRollover } from '@/lib/firestore/rollover';
import { z } from 'zod';

const MAX_ACTIONS = 4000; // rows + missing-student archives, generous headroom

// Firestore document ids: no slashes (a slashed id would still resolve inside
// this school's subtree, but only ever to a path that cannot exist, so it was
// already inert — this makes the constraint explicit) and no path segments.
const docId = z.string().min(1).max(128).regex(/^[^/]+$/, 'Invalid document id');

const moveFields = {
  studentDocId: docId,
  firstName: z.string().min(1).max(100),
  lastName: z.string().min(1).max(100),
  className: z.string().min(1).max(100),
  yearLevel: z.string().max(32).optional(),
  // Same format guard as create actions — a matched row's email can still be
  // written (update-if-unlinked), so it must be equally well-formed.
  parentEmail: z
    .string()
    .max(254)
    .optional()
    .refine((v) => !v || /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v), 'Invalid parent email'),
};

const actionSchema = z.discriminatedUnion('action', [
  z.object({ action: z.literal('move'), ...moveFields }),
  z.object({ action: z.literal('backfill_move'), ...moveFields, externalId: z.string().min(1).max(64) }),
  z.object({ action: z.literal('restore_move'), ...moveFields }),
  z.object({
    action: z.literal('create'),
    externalId: z.string().max(64).optional(),
    firstName: z.string().min(1).max(100),
    lastName: z.string().min(1).max(100),
    className: z.string().min(1).max(100),
    yearLevel: z.string().max(32).optional(),
    parentEmail: z
      .string()
      .max(254)
      .optional()
      .refine((v) => !v || /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v), 'Invalid parent email'),
    readingLevel: z.string().max(64).optional(),
  }),
  z.object({
    action: z.literal('archive'),
    studentDocId: docId,
    reason: z.enum(['graduated', 'left']),
  }),
]);

const commitSchema = z.object({
  importId: z.string().uuid('importId must be a UUID'),
  plan: z.object({
    targetAcademicYear: z.number().int().min(2020).max(2100),
    actions: z.array(actionSchema).min(1).max(MAX_ACTIONS),
    classesToDeactivate: z.array(docId).max(200).default([]),
  }),
});

export async function POST(request: NextRequest) {
  const session = await getSession({ requireMutable: true });
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Only school admins can run the rollover import' }, { status: 403 });
  }
  const impersonationBlock = assertNotImpersonating(session);
  if (impersonationBlock) return impersonationBlock;

  try {
    const body = await request.json();
    const { importId, plan } = commitSchema.parse(body);
    const currentAcademicYear = await getCurrentAcademicYear();
    if (plan.targetAcademicYear !== currentAcademicYear + 1) {
      return NextResponse.json(
        { error: `The active school-year transition is ${currentAcademicYear} to ${currentAcademicYear + 1}. Refresh the page and try again.` },
        { status: 409 }
      );
    }
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
