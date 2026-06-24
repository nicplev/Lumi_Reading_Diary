import { adminDb } from '@/lib/firebase/admin';

export interface StudentAchievement {
  id: string;
  name: string;
  description: string;
  icon: string;
  category: string;
  rarity: string;
  earnedAt: Date | null;
}

/**
 * Read-only list of a student's earned achievements (stored as an array on the
 * student doc by the detectAchievements Cloud Function), newest first.
 */
export async function getStudentAchievements(
  schoolId: string,
  studentId: string
): Promise<StudentAchievement[]> {
  const doc = await adminDb.collection('schools').doc(schoolId).collection('students').doc(studentId).get();
  if (!doc.exists) return [];
  const arr = doc.data()?.achievements;
  if (!Array.isArray(arr)) return [];

  return arr
    .map((a): StudentAchievement => ({
      id: a.id ?? '',
      name: a.name ?? '',
      description: a.description ?? '',
      icon: a.icon ?? '🏅',
      category: a.category ?? 'general',
      rarity: a.rarity ?? 'common',
      earnedAt: a.earnedAt?.toDate?.() ?? null,
    }))
    .sort((x, y) => (y.earnedAt?.getTime() ?? 0) - (x.earnedAt?.getTime() ?? 0));
}
