import { adminDb } from '@/lib/firebase/admin';
import { FieldValue } from 'firebase-admin/firestore';

// Matches the app's ClassModel.defaultComprehensionQuestion.
export const DEFAULT_COMPREHENSION_QUESTION = 'Tell us about what you read tonight.';

export async function getComprehensionQuestion(
  schoolId: string,
  classId: string
): Promise<string | null> {
  const doc = await adminDb.collection('schools').doc(schoolId).collection('classes').doc(classId).get();
  if (!doc.exists) return null;
  const settings = doc.data()?.settings as { comprehensionQuestion?: unknown } | undefined;
  const raw = settings?.comprehensionQuestion;
  return typeof raw === 'string' && raw.trim() ? raw : null;
}

/**
 * Sets the per-class comprehension question. Mirrors the app: when the value is
 * empty or equals the default, the field is DELETED so reads fall back to the
 * default (no stale/redundant data). Returns the stored value (or null = default).
 */
export async function setComprehensionQuestion(
  schoolId: string,
  classId: string,
  value: string
): Promise<string | null> {
  const trimmed = value.trim();
  const ref = adminDb.collection('schools').doc(schoolId).collection('classes').doc(classId);
  if (!trimmed || trimmed === DEFAULT_COMPREHENSION_QUESTION) {
    await ref.update({ 'settings.comprehensionQuestion': FieldValue.delete() });
    return null;
  }
  await ref.update({ 'settings.comprehensionQuestion': trimmed });
  return trimmed;
}
