import { adminDb } from '@/lib/firebase/admin';
import { getCurrentAcademicYear, isRenewalWindowOpen } from '@/lib/access';
import {
  classifyRollover,
  type ExistingClass,
  type ExistingStudent,
  type RolloverClassification,
  type RolloverCSVRow,
} from '@/lib/rollover/classify';

export interface RolloverPreview extends RolloverClassification {
  targetAcademicYear: number;
  /** Soft warning — the Oct→Feb renewal window isn't open right now. */
  outsideRenewalWindow: boolean;
}

/**
 * Dry-run classification of a rollover CSV against the school's current
 * students and classes. Reads everything, writes NOTHING — safe to run
 * anywhere, any time. The commit endpoint receives the plan the admin
 * resolves from this preview.
 */
export async function previewRollover(
  schoolId: string,
  rows: RolloverCSVRow[],
  targetAcademicYear?: number
): Promise<RolloverPreview> {
  const schoolRef = adminDb.collection('schools').doc(schoolId);
  const [studentsSnap, classesSnap, currentYear] = await Promise.all([
    // All students — archived included (restore-matching needs them).
    schoolRef.collection('students').get(),
    // All classes — deactivated included (rename/name-clash detection).
    schoolRef.collection('classes').get(),
    getCurrentAcademicYear(),
  ]);

  const students: ExistingStudent[] = studentsSnap.docs.map((doc) => {
    const d = doc.data();
    const additional = (d.additionalInfo ?? {}) as Record<string, unknown>;
    return {
      docId: doc.id,
      externalId: typeof d.studentId === 'string' && d.studentId.trim() !== '' ? d.studentId.trim() : null,
      firstName: d.firstName ?? '',
      lastName: d.lastName ?? '',
      classId: d.classId ?? '',
      isActive: d.isActive ?? true,
      yearLevel: typeof additional.yearLevel === 'string' && additional.yearLevel.trim() !== ''
        ? additional.yearLevel.trim()
        : null,
      graduated: additional.graduated === true,
      hasParentLink: Array.isArray(d.parentIds) && d.parentIds.length > 0,
    };
  });

  const classes: ExistingClass[] = classesSnap.docs.map((doc) => {
    const d = doc.data();
    return {
      docId: doc.id,
      name: typeof d.name === 'string' ? d.name : '',
      yearLevel: typeof d.yearLevel === 'string' && d.yearLevel.trim() !== '' ? d.yearLevel.trim() : null,
      isActive: d.isActive ?? true,
    };
  });

  const year = targetAcademicYear ?? currentYear;
  return {
    ...classifyRollover(rows, students, classes),
    targetAcademicYear: year,
    outsideRenewalWindow: !isRenewalWindowOpen(year),
  };
}
