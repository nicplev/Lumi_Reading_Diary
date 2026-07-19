import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import { adminDb } from '@/lib/firebase/admin';
import { createDemoAllocation } from '@/lib/firestore/demo-allocations';
import {
  auditDemoAllocationMutation,
  authorizeDemoAllocationMutation,
  type AuthorizedDemoAllocationSession,
  DemoAllocationSecurityError,
} from '@/lib/demo/allocation-security';

const dateString = z.string().trim().min(10).max(40).refine(
  (value) => Number.isFinite(Date.parse(value)),
  'Invalid date',
);
const schema = z.object({
  classId: z.string().trim().min(1).max(128),
  type: z.literal('byTitle'),
  cadence: z.literal('weekly'),
  targetMinutes: z.number().int().min(1).max(180),
  startDate: dateString,
  endDate: dateString,
  studentIds: z.array(z.string().trim().min(1).max(128)).max(100).default([]),
  assignmentItems: z.array(z.object({
    title: z.string().trim().min(1).max(240),
    bookId: z.string().trim().min(1).max(128).optional(),
    isbn: z.string().trim().max(32).optional(),
  }).strict()).min(1).max(30),
}).strict();

export async function POST(request: NextRequest) {
  let authorized: AuthorizedDemoAllocationSession | undefined;
  try {
    authorized = await authorizeDemoAllocationMutation(
      request,
      'allocation_create',
    );
    const { session, generationId } = authorized;
    const data = schema.parse(await request.json());
    if (new Date(data.startDate) > new Date(data.endDate)) {
      return NextResponse.json({ error: 'End date must be after start date.' }, { status: 400 });
    }

    const schoolRef = adminDb.collection('schools').doc(session.schoolId);
    const classRef = schoolRef.collection('classes').doc(data.classId);
    const [classSnapshot, ...studentSnapshots] = await adminDb.getAll(
      classRef,
      ...data.studentIds.map((id) => schoolRef.collection('students').doc(id)),
    );
    if (!classSnapshot.exists) {
      return NextResponse.json({ error: 'Demo class not found.' }, { status: 404 });
    }
    if (studentSnapshots.some(
      (snapshot) => !snapshot.exists || snapshot.data()?.classId !== data.classId,
    )) {
      return NextResponse.json({ error: 'A selected student is not in this demo class.' }, { status: 400 });
    }

    const id = await createDemoAllocation(session.schoolId, generationId, {
      classId: data.classId,
      studentIds: data.studentIds,
      targetMinutes: data.targetMinutes,
      startDate: data.startDate,
      endDate: data.endDate,
      assignmentItems: data.assignmentItems,
      actorId: session.uid,
    });
    await auditDemoAllocationMutation(session, 'allocation_create', 'succeeded').catch(() => undefined);
    return NextResponse.json({ id }, { status: 201 });
  } catch (error) {
    if (authorized) {
      await auditDemoAllocationMutation(
        authorized.session,
        'allocation_create',
        'rejected',
      ).catch(() => undefined);
    }
    if (error instanceof DemoAllocationSecurityError) {
      return NextResponse.json({ error: error.message }, { status: error.status });
    }
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0]?.message ?? 'Invalid request.' }, { status: 400 });
    }
    if (error instanceof Error && error.message === 'DEMO_GENERATION_EXPIRED') {
      return NextResponse.json({ error: 'The demo was refreshed. Sign in again.' }, { status: 409 });
    }
    console.error(
      'Demo allocation creation failed',
      error instanceof Error ? error.name : typeof error,
    );
    return NextResponse.json({ error: 'Could not create the demo allocation.' }, { status: 500 });
  }
}
