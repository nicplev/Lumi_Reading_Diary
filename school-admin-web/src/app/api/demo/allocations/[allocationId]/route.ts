import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import { deleteDemoAllocation } from '@/lib/firestore/demo-allocations';
import {
  auditDemoAllocationMutation,
  authorizeDemoAllocationMutation,
  type AuthorizedDemoAllocationSession,
  DemoAllocationSecurityError,
} from '@/lib/demo/allocation-security';

const idSchema = z.string().trim().min(1).max(128).regex(/^[A-Za-z0-9_-]+$/);

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ allocationId: string }> },
) {
  let authorized: AuthorizedDemoAllocationSession | undefined;
  try {
    authorized = await authorizeDemoAllocationMutation(
      request,
      'allocation_delete',
    );
    const { session, generationId } = authorized;
    const allocationId = idSchema.parse((await params).allocationId);
    await deleteDemoAllocation(session.schoolId, generationId, allocationId);
    await auditDemoAllocationMutation(session, 'allocation_delete', 'succeeded').catch(() => undefined);
    return NextResponse.json({ success: true });
  } catch (error) {
    if (authorized) {
      await auditDemoAllocationMutation(
        authorized.session,
        'allocation_delete',
        'rejected',
      ).catch(() => undefined);
    }
    if (error instanceof DemoAllocationSecurityError) {
      return NextResponse.json({ error: error.message }, { status: error.status });
    }
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: 'Invalid allocation.' }, { status: 400 });
    }
    if (error instanceof Error && error.message === 'ALLOCATION_NOT_FOUND') {
      return NextResponse.json({ error: 'Allocation not found.' }, { status: 404 });
    }
    if (error instanceof Error && error.message === 'SEEDED_DEMO_ALLOCATION_IMMUTABLE') {
      return NextResponse.json(
        { error: 'Seeded demo allocations cannot be deleted.' },
        { status: 403 },
      );
    }
    if (error instanceof Error && error.message === 'DEMO_GENERATION_EXPIRED') {
      return NextResponse.json({ error: 'The demo was refreshed. Sign in again.' }, { status: 409 });
    }
    console.error(
      'Demo allocation deletion failed',
      error instanceof Error ? error.name : typeof error,
    );
    return NextResponse.json({ error: 'Could not delete the demo allocation.' }, { status: 500 });
  }
}
