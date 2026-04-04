import { adminDb } from '@/lib/firebase/admin';
import type { School, ReadingLevelSchema } from '@/lib/types';

export async function updateSchool(
  schoolId: string,
  data: Partial<Pick<School, 'name' | 'displayName' | 'logoUrl' | 'primaryColor' | 'secondaryColor' | 'levelSchema' | 'customLevels' | 'levelColors' | 'timezone' | 'address' | 'contactEmail' | 'contactPhone' | 'quietHours'>> & {
    termDates?: Record<string, string>;
    parentCommentSettings?: { enabled: boolean; freeTextEnabled: boolean; customPresets: { id: string; name: string; chips: string[] }[] };
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
  if (data.termDates !== undefined) {
    update.termDates = Object.fromEntries(
      Object.entries(data.termDates).map(([k, v]) => [k, new Date(v)])
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
      Object.entries(data.termDates ?? {}).map(([k, v]) => [k, (v as { toDate: () => Date }).toDate()])
    ),
    quietHours: data.quietHours ?? {},
    timezone: data.timezone ?? 'UTC',
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
  };
}
