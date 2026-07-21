import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import { getStudent } from '@/lib/firestore/students';
import { assignDemoIsbnsToStudentWeek } from '@/lib/firestore/demo-allocations';
import {
  auditDemoAllocationMutation,
  authorizeDemoAllocationMutation,
  type AuthorizedDemoAllocationSession,
} from '@/lib/demo/allocation-security';
// Base type: catches both DemoAllocationSecurityError and anything raised by
// the shared origin/rate-limit guards it now delegates to.
import { RequestGuardError } from '@/lib/http/request-guards';

const schema = z.object({
  studentId: z.string().trim().min(1).max(128),
  isbns: z.array(z.string().trim().min(1).max(32)).min(1).max(20),
  weekStart: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Invalid week'),
}).strict();

export async function POST(request: NextRequest) {
  let authorized: AuthorizedDemoAllocationSession | undefined;
  try {
    authorized = await authorizeDemoAllocationMutation(
      request,
      'isbn_assign',
    );
    const { session, generationId } = authorized;
    const data = schema.parse(await request.json());
    const student = await getStudent(session.schoolId, data.studentId);
    if (!student?.classId) {
      return NextResponse.json({ error: 'Student not found in a demo class.' }, { status: 404 });
    }

    const result = await assignDemoIsbnsToStudentWeek(
      session.schoolId,
      generationId,
      {
        studentId: data.studentId,
        classId: student.classId,
        isbns: data.isbns,
        weekStart: data.weekStart,
        actorId: session.uid,
      },
    );
    await auditDemoAllocationMutation(session, 'isbn_assign', 'succeeded').catch(() => undefined);
    return NextResponse.json(result);
  } catch (error) {
    if (authorized) {
      await auditDemoAllocationMutation(
        authorized.session,
        'isbn_assign',
        'rejected',
      ).catch(() => undefined);
    }
    if (error instanceof RequestGuardError) {
      return NextResponse.json({ error: error.message }, { status: error.status });
    }
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0]?.message ?? 'Invalid request.' }, { status: 400 });
    }
    if (error instanceof Error && error.message === 'SEEDED_DEMO_ALLOCATION_IMMUTABLE') {
      return NextResponse.json(
        { error: 'Seeded demo allocations are read-only. Choose another student or week.' },
        { status: 409 },
      );
    }
    if (error instanceof Error && error.message === 'DEMO_GENERATION_EXPIRED') {
      return NextResponse.json({ error: 'The demo was refreshed. Sign in again.' }, { status: 409 });
    }
    console.error(
      'Demo ISBN assignment failed',
      error instanceof Error ? error.name : typeof error,
    );
    return NextResponse.json({ error: 'Could not assign the demo book.' }, { status: 500 });
  }
}
