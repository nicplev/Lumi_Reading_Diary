import { adminDb } from '@/lib/firebase/admin';
import { isActiveSubscriptionStatus } from '@/lib/types';

// Mirrors functions/src/access.ts for the school-admin web portal. The Cloud
// Functions remain the canonical writers (rollover cron, subscription trigger);
// this lets the renewals API grant access server-side without a round-trip to
// the callable. Keep the two in sync.

export const DEFAULT_TIMEZONE = 'Australia/Sydney';
export const ROLLOVER_DAY = 25;
const YEAR_LADDER = ['Prep', '1', '2', '3', '4', '5', '6'];
const PREP_SYNONYMS = ['prep', 'foundation', 'kindergarten', 'kinder', 'k', 'f'];

function localPart(d: Date, opt: Intl.DateTimeFormatOptions): number {
  return Number(
    new Intl.DateTimeFormat('en-CA', { timeZone: DEFAULT_TIMEZONE, ...opt }).format(d)
  );
}

/** The academic year an instant falls in (AU; pre-rollover Jan = prior year). */
export function academicYearForDate(d: Date): number {
  const year = localPart(d, { year: 'numeric' });
  const month = localPart(d, { month: 'numeric' });
  const day = localPart(d, { day: 'numeric' });
  if (month === 1 && day < ROLLOVER_DAY) return year - 1;
  return year;
}

/** Absolute hard-expiry: end of 31 January of the following year, local time. */
export function hardExpiryFor(academicYear: number): Date {
  const expiryYear = academicYear + 1;
  const naiveUtc = Date.UTC(expiryYear, 0, 31, 23, 59, 59);
  const offsetMs = timezoneOffsetMs(new Date(naiveUtc));
  return new Date(naiveUtc - offsetMs);
}

function timezoneOffsetMs(d: Date): number {
  const dtf = new Intl.DateTimeFormat('en-US', {
    timeZone: DEFAULT_TIMEZONE,
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
  });
  const map: Record<string, number> = {};
  for (const p of dtf.formatToParts(d)) {
    if (p.type !== 'literal') map[p.type] = Number(p.value);
  }
  const asUtc = Date.UTC(
    map.year, map.month - 1, map.day,
    map.hour === 24 ? 0 : map.hour, map.minute, map.second
  );
  return asUtc - d.getTime();
}

/** Advance a recognised year level; flag graduates past the top. */
export function nextYearLevel(current: string | null | undefined): {
  next: string | null;
  graduated: boolean;
  changed: boolean;
} {
  if (current == null || current === '') {
    return { next: current ?? null, graduated: false, changed: false };
  }
  const normalised = PREP_SYNONYMS.includes(current.trim().toLowerCase())
    ? 'Prep'
    : current.trim();
  const idx = YEAR_LADDER.indexOf(normalised);
  if (idx === -1) return { next: current, graduated: false, changed: false };
  if (idx === YEAR_LADDER.length - 1) {
    return { next: normalised, graduated: true, changed: false };
  }
  return { next: YEAR_LADDER[idx + 1], graduated: false, changed: true };
}

/** Current academic year from config/academicYear, else derived from today. */
export async function getCurrentAcademicYear(): Promise<number> {
  const cfg = await adminDb.collection('config').doc('academicYear').get();
  const v = cfg.data()?.currentAcademicYear;
  if (typeof v === 'number') return v;
  return academicYearForDate(new Date());
}

/**
 * Whether a materialised `student.access` map is live right now: status
 * 'active' AND not past its hard expiry. Mirrors StudentModel.isActive
 * (app) and studentAccessLive (rules). A missing/legacy map is NOT live.
 */
export function isStudentAccessLive(
  access: unknown,
  now: Date = new Date()
): boolean {
  if (access == null || typeof access !== 'object') return false;
  const a = access as { status?: unknown; expiresAt?: unknown };
  if (a.status !== 'active') return false;
  const raw = a.expiresAt as { toDate?: () => Date } | Date | string | undefined;
  const expiry =
    raw instanceof Date ? raw :
    typeof raw === 'string' ? new Date(raw) :
    typeof raw?.toDate === 'function' ? raw.toDate() : null;
  if (!(expiry instanceof Date) || isNaN(expiry.getTime())) return false;
  return expiry.getTime() > now.getTime();
}

/** Whether the school's subscription for `year` grants active access. */
export async function isSchoolSubActive(
  schoolId: string,
  year: number
): Promise<boolean> {
  const sub = await adminDb
    .collection('schoolSubscriptions')
    .doc(`${schoolId}_${year}`)
    .get();
  return sub.exists && isActiveSubscriptionStatus(sub.data()?.status as string);
}

/**
 * The annual renewal window for carrying students into `targetYear`: opens 1
 * October of the prior year (start of Term 4) and closes end of February of the
 * target year, in the school timezone. Outside it the portal shows a soft "it's
 * early" warning but still allows renewal — off-cycle exceptions are permitted.
 */
export function isRenewalWindowOpen(targetYear: number, now: Date = new Date()): boolean {
  const opensNaive = Date.UTC(targetYear - 1, 9, 1, 0, 0, 0); // 1 Oct, prior year
  const closesNaive = Date.UTC(targetYear, 2, 1, 0, 0, 0); // 1 Mar, target year
  const opensAt = opensNaive - timezoneOffsetMs(new Date(opensNaive));
  const closesAt = closesNaive - timezoneOffsetMs(new Date(closesNaive));
  const t = now.getTime();
  return t >= opensAt && t < closesAt;
}

export interface RenewalReminder {
  /** Show the dashboard reminder at all. */
  due: boolean;
  /** Escalate the copy — the last few weeks before the 31 Jan expiry. */
  urgent: boolean;
  /** The academic year renewal should carry students INTO. */
  targetYear: number;
}

/**
 * Whether the admin dashboard should nudge about annual renewal. The current
 * cohort's access hard-expires ~31 Jan; renewal into the next year should
 * happen before that. Reminder runs 1 Dec → the 31 Jan cliff (school-local),
 * turning urgent once January starts. Outside that window it's silent — the
 * Renewals page is always available for off-cycle exceptions.
 */
export function renewalReminder(now: Date = new Date()): RenewalReminder {
  const year = academicYearForDate(now); // pre-rollover Jan still = prior cohort
  const month = localPart(now, { month: 'numeric' });
  const day = localPart(now, { day: 'numeric' });
  const inDecember = month === 12;
  const inJanuaryBeforeCliff = month === 1 && day <= 31;
  return {
    due: inDecember || inJanuaryBeforeCliff,
    urgent: inJanuaryBeforeCliff,
    targetYear: year + 1,
  };
}
