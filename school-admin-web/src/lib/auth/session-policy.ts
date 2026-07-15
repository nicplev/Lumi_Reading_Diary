export type PortalRole = 'teacher' | 'schoolAdmin';

export interface CurrentMembership {
  isActive?: unknown;
  pendingDeletion?: unknown;
  role?: unknown;
}

export function isCurrentMembershipValid(
  exists: boolean,
  membership: CurrentMembership | undefined,
  cookieRole: PortalRole,
): boolean {
  return (
    exists &&
    membership?.isActive !== false &&
    membership?.pendingDeletion !== true &&
    membership?.role === cookieRole
  );
}

export function allowVerifiedJwtAfterMembershipLookupFailure(
  requireMutable: boolean,
): boolean {
  return !requireMutable;
}
