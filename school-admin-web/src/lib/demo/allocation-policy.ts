export interface DemoAllocationSessionShape {
  role?: unknown;
  mfaExemptReason?: unknown;
  demoAllocationMutations?: unknown;
  demoGenerationId?: unknown;
}

export function hasDemoAllocationCapability(
  session: DemoAllocationSessionShape | null,
): session is DemoAllocationSessionShape & { demoGenerationId: string } {
  return Boolean(
    session &&
      session.role === 'schoolAdmin' &&
      session.mfaExemptReason === 'isolatedDemoReadOnly' &&
      session.demoAllocationMutations === true &&
      typeof session.demoGenerationId === 'string' &&
      session.demoGenerationId.length > 0,
  );
}

export function isCurrentDemoAllocationAuthority(input: {
  schoolExists: boolean;
  schoolIsDemo: unknown;
  membershipExists: boolean;
  membershipRole: unknown;
  membershipActive: unknown;
  membershipPendingDeletion: unknown;
  reseedState: unknown;
  reseedSchoolId: unknown;
  reseedLeaseId: unknown;
  sessionSchoolId: string;
  sessionGenerationId: string;
}): boolean {
  return (
    input.schoolExists &&
    input.schoolIsDemo === true &&
    input.membershipExists &&
    input.membershipRole === 'schoolAdmin' &&
    input.membershipActive !== false &&
    input.membershipPendingDeletion !== true &&
    input.reseedState === 'succeeded' &&
    input.reseedSchoolId === input.sessionSchoolId &&
    typeof input.reseedLeaseId === 'string' &&
    input.reseedLeaseId === input.sessionGenerationId
  );
}

