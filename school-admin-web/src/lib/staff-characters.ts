/**
 * Staff (admin + teacher) profile-character catalogue — the staff counterpart of
 * `lib/characters.ts`. Admins choose an Admin Lumi (`la_*`) variant; teachers
 * choose a Male Teacher (`mt_*`) or Female Teacher (`ft_*`) variant. The id is
 * the PNG filename stem under `public/staff-characters/`. Slugs are disjoint
 * from the student catalogue, so a single Avatar can resolve either.
 */

const ADMIN_IDS = [
  'la_default',
  'la_blue',
  'la_green',
  'la_lblue',
  'la_orange',
  'la_pink',
  'la_purple',
  'la_yellow',
] as const;

const TEACHER_IDS = [
  // Male Teacher
  'mt_default',
  'mt_blue',
  'mt_green',
  'mt_lblue',
  'mt_orange',
  'mt_pink',
  'mt_purple',
  'mt_yellow',
  // Female Teacher
  'ft_default',
  'ft_blue',
  'ft_green',
  'ft_lblue',
  'ft_orange',
  'ft_pink',
  'ft_purple',
  'ft_yellow',
] as const;

const STAFF_CHARACTER_IDS: ReadonlySet<string> = new Set([...ADMIN_IDS, ...TEACHER_IDS]);

/** Public path to the staff character PNG, or null if unset/unrecognised. */
export function staffCharacterImageSrc(characterId?: string | null): string | null {
  if (!characterId) return null;
  return STAFF_CHARACTER_IDS.has(characterId) ? `/staff-characters/${characterId}.png` : null;
}

/** The character ids a given staff role may pick from. */
export function allowedStaffCharacterIds(role: 'teacher' | 'schoolAdmin'): readonly string[] {
  return role === 'schoolAdmin' ? ADMIN_IDS : TEACHER_IDS;
}

/** True if `characterId` is a valid choice for `role` (category matches role). */
export function isStaffCharacterAllowed(role: 'teacher' | 'schoolAdmin', characterId: string): boolean {
  return allowedStaffCharacterIds(role).includes(characterId);
}
