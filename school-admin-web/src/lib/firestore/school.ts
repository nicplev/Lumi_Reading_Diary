import { adminDb } from '@/lib/firebase/admin';
import { DEFAULT_TIMEZONE } from '@/lib/time-core';
import type { School, ReadingLevelSchema, AchievementThresholds, AchievementCustomization } from '@/lib/types';

/**
 * Coerce a stored term-date value (Timestamp, Date, or ISO string) to a Date,
 * or null when unparseable — one malformed entry must never make getSchool
 * (and everything downstream, like the analytics route) throw.
 */
function coerceTermDate(v: unknown): Date | null {
  const maybe = v as { toDate?: () => Date } | Date | string | null | undefined;
  const d =
    maybe instanceof Date ? maybe :
    typeof maybe === 'string' ? new Date(maybe) :
    typeof maybe?.toDate === 'function' ? maybe.toDate() : null;
  return d instanceof Date && !isNaN(d.getTime()) ? d : null;
}

export async function updateSchool(
  schoolId: string,
  data: Partial<Pick<School, 'name' | 'displayName' | 'logoUrl' | 'primaryColor' | 'secondaryColor' | 'levelSchema' | 'customLevels' | 'levelColors' | 'timezone' | 'address' | 'contactEmail' | 'contactPhone' | 'quietHours'>> & {
    termDates?: Record<string, string>;
    parentCommentSettings?: { enabled: boolean; freeTextEnabled: boolean; customPresets: { id: string; name: string; chips: string[] }[] };
    quickLoggingSettings?: { enabled: boolean };
    comprehensionRecordingSettings?: { enabled: boolean };
    messagingSettings?: { enabled: boolean };
    achievementThresholds?: AchievementThresholds;
    achievementCustomization?: AchievementCustomization;
  }
): Promise<void> {
  const update: Record<string, unknown> = {};
  if (data.name !== undefined) update.name = data.name;
  if (data.displayName !== undefined) update.displayName = data.displayName;
  if (data.logoUrl !== undefined) update.logoUrl = data.logoUrl;
  if (data.primaryColor !== undefined) update.primaryColor = data.primaryColor;
  if (data.secondaryColor !== undefined) update.secondaryColor = data.secondaryColor;
  if (data.levelSchema !== undefined) update.levelSchema = data.levelSchema;
  if (data.customLevels !== undefined) update.customLevels = data.customLevels;
  if (data.levelColors !== undefined) update.levelColors = data.levelColors;
  if (data.timezone !== undefined) update.timezone = data.timezone;
  if (data.address !== undefined) update.address = data.address;
  if (data.contactEmail !== undefined) update.contactEmail = data.contactEmail;
  if (data.contactPhone !== undefined) update.contactPhone = data.contactPhone;
  if (data.quietHours !== undefined) update.quietHours = data.quietHours;
  if (data.parentCommentSettings !== undefined) {
    update['settings.parentComments'] = data.parentCommentSettings;
  }
  if (data.quickLoggingSettings !== undefined) {
    update['settings.quickLogging'] = data.quickLoggingSettings;
  }
  if (data.comprehensionRecordingSettings !== undefined) {
    update['settings.comprehensionRecording'] = data.comprehensionRecordingSettings;
  }
  if (data.messagingSettings !== undefined) {
    update['settings.messaging'] = data.messagingSettings;
  }
  if (data.achievementThresholds !== undefined) {
    update['settings.achievementThresholds'] = data.achievementThresholds;
  }
  if (data.achievementCustomization !== undefined) {
    update['settings.achievementCustomization'] = data.achievementCustomization;
  }
  if (data.termDates !== undefined) {
    // Drop empty/invalid values instead of writing Invalid Dates (which the
    // Admin SDK rejects, failing the whole save when an admin clears a field).
    // The map is replaced wholesale, so a dropped key IS the cleared state.
    update.termDates = Object.fromEntries(
      Object.entries(data.termDates)
        .map(([k, v]) => [k, v ? new Date(v) : null] as const)
        .filter((e): e is readonly [string, Date] =>
          e[1] instanceof Date && !isNaN(e[1].getTime()))
    );
  }

  await adminDb.collection('schools').doc(schoolId).update(update);
}

export async function getSchool(schoolId: string): Promise<School | null> {
  const doc = await adminDb.collection('schools').doc(schoolId).get();
  if (!doc.exists) return null;
  const data = doc.data()!;

  return {
    id: doc.id,
    name: data.name ?? '',
    logoUrl: data.logoUrl,
    primaryColor: data.primaryColor,
    secondaryColor: data.secondaryColor,
    levelSchema: (data.levelSchema as ReadingLevelSchema) ?? 'aToZ',
    customLevels: data.customLevels,
    levelColors: data.levelColors,
    termDates: Object.fromEntries(
      Object.entries(data.termDates ?? {})
        .map(([k, v]) => [k, coerceTermDate(v)] as const)
        .filter((e): e is readonly [string, Date] => e[1] !== null)
    ),
    quietHours: data.quietHours ?? {},
    // Default matches the functions-side DEFAULT_TIMEZONE (Australia/Sydney)
    // so an unset school buckets days the same way everywhere.
    timezone: data.timezone ?? DEFAULT_TIMEZONE,
    address: data.address,
    contactEmail: data.contactEmail,
    contactPhone: data.contactPhone,
    isActive: data.isActive ?? true,
    createdAt: data.createdAt?.toDate() ?? new Date(),
    createdBy: data.createdBy ?? '',
    settings: data.settings,
    studentCount: data.studentCount ?? 0,
    teacherCount: data.teacherCount ?? 0,
    subscriptionPlan: data.subscriptionPlan,
    subscriptionExpiry: data.subscriptionExpiry?.toDate(),
    accessMode: data.accessMode ?? 'whole_school_paid',
  };
}
