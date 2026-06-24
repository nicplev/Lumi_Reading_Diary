import { adminDb } from '@/lib/firebase/admin';
import { FieldValue } from 'firebase-admin/firestore';
import { hardExpiryFor, nextYearLevel } from '@/lib/access';

export interface RenewalRosterEntry {
  studentId: string;
  firstName: string;
  lastName: string;
  classId: string;
  currentYearLevel: string | null;
  /** Suggested year level after the bump (pre-filled in the UI). */
  nextYearLevel: string | null;
  graduated: boolean;
  /** academicYear the student's current access is for, if any. */
  accessYear: number | null;
  /** Whether the student is already renewed into the target year. */
  alreadyRenewed: boolean;
}

/**
 * Pre-loads the renewal roster: the school's active students, with year level
 * bumped one rung and graduates flagged, plus whether each is already renewed
 * into the target year. Graduates are de-selected by default in the UI; the
 * rest are pre-ticked.
 */
export async function getRenewalRoster(
  schoolId: string,
  targetAcademicYear: number
): Promise<RenewalRosterEntry[]> {
  const snap = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('students')
    .where('isActive', '==', true)
    .get();

  return snap.docs.map((doc) => {
    const d = doc.data();
    const additional = (d.additionalInfo ?? {}) as Record<string, unknown>;
    const currentYearLevel = (additional.yearLevel as string | undefined) ?? null;
    const ladder = nextYearLevel(currentYearLevel);
    const accessYear = (d.access?.academicYear as number | undefined) ?? null;
    return {
      studentId: doc.id,
      firstName: d.firstName ?? '',
      lastName: d.lastName ?? '',
      classId: d.classId ?? '',
      currentYearLevel,
      nextYearLevel: ladder.next,
      graduated: ladder.graduated,
      accessYear,
      alreadyRenewed: accessYear === targetAcademicYear,
    };
  });
}

export interface RenewResult {
  renewed: number;
  graduates: number;
}

/**
 * Grant access for `academicYear` to the selected students (source:
 * school_renewal), bumping recognised year levels and flagging graduates.
 * Mirrors the renewStudents Cloud Function so either entry point is consistent.
 * Chunked into batches of 400 (Firestore limit headroom).
 */
export async function renewStudents(
  schoolId: string,
  academicYear: number,
  studentIds: string[],
  grantedBy: string
): Promise<RenewResult> {
  const studentsCol = adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('students');

  const expiresAt = hardExpiryFor(academicYear);
  let renewed = 0;
  let graduates = 0;

  for (let i = 0; i < studentIds.length; i += 400) {
    const chunk = studentIds.slice(i, i + 400);
    const snaps = await adminDb.getAll(...chunk.map((id) => studentsCol.doc(id)));
    const batch = adminDb.batch();
    for (const snap of snaps) {
      if (!snap.exists) continue;
      const additional = (snap.data()?.additionalInfo ?? {}) as Record<string, unknown>;
      const ladder = nextYearLevel(additional.yearLevel as string | undefined);

      const update: Record<string, unknown> = {
        access: {
          status: 'active',
          academicYear,
          expiresAt,
          source: 'school_renewal',
          grantedAt: FieldValue.serverTimestamp(),
          grantedBy,
        },
      };
      if (ladder.changed && ladder.next != null) {
        update['additionalInfo.yearLevel'] = ladder.next;
      }
      if (ladder.graduated) {
        update['additionalInfo.graduated'] = true;
        graduates++;
      }
      batch.update(snap.ref, update);
      renewed++;
    }
    await batch.commit();
  }

  return { renewed, graduates };
}
