// Field-level visibility for the school document.
//
// GET /api/settings is read broadly by teacher-reachable UI (global theming,
// term dates, level schema), so it cannot be admin-gated. But the whole school
// doc also carries commercial/contact fields that only the admin-only settings
// page needs. Teachers get the branding/config they use, minus these.

export const ADMIN_ONLY_SCHOOL_FIELDS = [
  "subscription",
  "subscriptionExpiry",
  "subscriptionStatus",
  "plan",
  "access",
  "accessMode",
  "isDemo",
  "createdBy",
  "contactEmail",
  "contactPhone",
  "address",
  "billing",
] as const;

// Returns the payload unchanged for a schoolAdmin; for any other role returns
// a shallow copy with the admin-only fields removed. Pure.
export function stripAdminOnlySchoolFields(
  payload: Record<string, unknown>,
  role: string,
): Record<string, unknown> {
  if (role === "schoolAdmin") return payload;
  const copy = { ...payload };
  for (const key of ADMIN_ONLY_SCHOOL_FIELDS) delete copy[key];
  return copy;
}
