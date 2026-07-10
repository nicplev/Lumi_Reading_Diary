import { adminDb } from '@/lib/firebase/admin';
import { FieldValue } from 'firebase-admin/firestore';
import { hardExpiryFor, yearLevelForRenewal } from '@/lib/access';
import { isActiveSubscriptionStatus } from '@/lib/types';

export interface RenewalRosterEntry {
  studentId: string;
  firstName: string;
  lastName: string;
  classId: string;
  currentYearLevel: string | null;
  /** Suggested year level after the bump (pre-filled in the UI). */
  nextYearLevel: string | null;
  graduated: boolean;
  /**
   * A roster import or prior grant already set this student's year level for
   * the target year — renewal won't bump it again.
   */
  yearLevelSetByImport: boolean;
  /** academicYear the student's current access is for, if any. */
  accessYear: number | null;
  /** Current materialised access status, if any (for the Status column). */
  accessStatus: 'active' | 'expired' | 'suspended' | 'revoked' | null;
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
  const [snap, classesSnap] = await Promise.all([
    adminDb
      .collection('schools')
      .doc(schoolId)
      .collection('students')
      .where('isActive', '==', true)
      .get(),
    adminDb.collection('schools').doc(schoolId).collection('classes').get(),
  ]);

  // Year level lives on the class; a student inherits their class's year level
  // unless they carry an individual override (set when a prior rollover bumped
  // them). This is why the column was blank before — students rarely have an
  // individual yearLevel set.
  const classYearLevel = new Map<string, string>();
  classesSnap.docs.forEach((c) => {
    const yl = c.data().yearLevel;
    if (typeof yl === 'string' && yl.trim()) classYearLevel.set(c.id, yl.trim());
  });

  return snap.docs.map((doc) => {
    const d = doc.data();
    const additional = (d.additionalInfo ?? {}) as Record<string, unknown>;
    const individualYearLevel = (additional.yearLevel as string | undefined)?.trim() || null;
    const classId = (d.classId as string | undefined) ?? '';
    const currentYearLevel =
      individualYearLevel ?? (classId ? classYearLevel.get(classId) ?? null : null);
    const ladder = yearLevelForRenewal(
      currentYearLevel,
      additional.yearLevelSetForYear,
      targetAcademicYear
    );
    const accessYear = (d.access?.academicYear as number | undefined) ?? null;
    const accessStatus =
      (d.access?.status as 'active' | 'expired' | 'suspended' | 'revoked' | undefined) ?? null;
    return {
      studentId: doc.id,
      firstName: d.firstName ?? '',
      lastName: d.lastName ?? '',
      classId,
      currentYearLevel,
      nextYearLevel: ladder.next,
      graduated: ladder.graduated,
      yearLevelSetByImport: ladder.setByImport,
      accessYear,
      accessStatus,
      alreadyRenewed: accessYear === targetAcademicYear && accessStatus === 'active',
    };
  });
}

export interface RenewResult {
  renewed: number;
  graduates: number;
  skipped: number;
  /** Id of the recorded batch (for an immediate undo); null if nothing renewed. */
  batchId: string | null;
}

/** Per-student before-snapshot captured at renewal, so a batch can be undone. */
export interface RenewalBatchEntry {
  studentId: string;
  name: string;
  prevAccess: Record<string, unknown> | null;
  prevYearLevel: string | null;
  prevYearLevelSetForYear: number | null;
  prevGraduated: boolean;
  /** Whether this renewal bumped the year level (so undo knows to restore it). */
  bumped: boolean;
  /** Whether this renewal wrote the same-year idempotency marker. */
  markedYearLevelForYear: boolean;
  /** Whether this renewal flagged the student graduated. */
  graduated: boolean;
}

/** Client-facing summary of a recorded renewal batch (for the undo list). */
export interface RenewalBatchSummary {
  id: string;
  academicYear: number;
  count: number;
  status: 'applied' | 'undone';
  performedByName: string | null;
  performedAtIso: string | null;
  undoneAtIso: string | null;
}

/**
 * Grant access for `academicYear` to the selected students (source:
 * school_renewal), bumping recognised year levels and flagging graduates.
 * Records a `renewalBatches` doc with per-student before-snapshots so the whole
 * action can be undone (mistake recovery + audit trail). Student writes and
 * the undo record commit in one transaction (up to 400 students), making
 * retries and concurrent submissions idempotent.
 */
export async function renewStudents(
  schoolId: string,
  academicYear: number,
  studentIds: string[],
  grantedBy: string,
  grantedByName?: string
): Promise<RenewResult> {
  const studentsCol = adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('students');

  const expiresAt = hardExpiryFor(academicYear);
  const classesSnap = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('classes')
    .get();
  const classYearLevel = new Map<string, string>();
  classesSnap.docs.forEach((doc) => {
    const value = doc.data().yearLevel;
    if (typeof value === 'string' && value.trim()) classYearLevel.set(doc.id, value.trim());
  });

  if (studentIds.length > 400) {
    throw new Error('A renewal can include at most 400 students.');
  }

  const renewalRef = adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('renewalBatches')
    .doc();

  // Students and the corresponding undo/audit record commit atomically. The
  // transaction also serialises concurrent retries: once one request grants
  // target-year access, a racing request retries, sees it, and safely skips it.
  const transactionResult = await adminDb.runTransaction(async (transaction) => {
    const subscription = await transaction.get(
      adminDb.collection('schoolSubscriptions').doc(`${schoolId}_${academicYear}`)
    );
    if (
      !subscription.exists ||
      !isActiveSubscriptionStatus(subscription.data()?.status as string)
    ) {
      throw new Error(`School subscription is not active for ${academicYear}.`);
    }
    const snaps = await Promise.all(
      studentIds.map((studentId) => transaction.get(studentsCol.doc(studentId)))
    );
    const entries: RenewalBatchEntry[] = [];
    let graduates = 0;
    let skipped = 0;

    for (const snap of snaps) {
      if (!snap.exists) {
        skipped++;
        continue;
      }
      const data = snap.data() ?? {};
      // Never let a stale or forged selection reactivate an archived student.
      if (data.isActive !== true) {
        skipped++;
        continue;
      }
      if (
        data.access?.academicYear === academicYear &&
        data.access?.status === 'active'
      ) {
        // Idempotency guard: a client retry must not bump the year level twice
        // or create a second audit batch for the same grant.
        skipped++;
        continue;
      }
      const additional = (data.additionalInfo ?? {}) as Record<string, unknown>;
      const prevYearLevel = (additional.yearLevel as string | undefined) ?? null;
      const prevYearLevelSetForYear =
        typeof additional.yearLevelSetForYear === 'number'
          ? additional.yearLevelSetForYear
          : null;
      const prevGraduated = additional.graduated === true;
      // Skip the bump when the rollover import already set the level for this
      // (or a later) year — bumping again would skip the student a grade.
      const currentYearLevel =
        prevYearLevel ??
        (typeof data.classId === 'string' ? classYearLevel.get(data.classId) ?? null : null);
      const ladder = yearLevelForRenewal(
        currentYearLevel,
        additional.yearLevelSetForYear,
        academicYear
      );

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
        update['additionalInfo.yearLevelSetForYear'] = academicYear;
      }
      if (ladder.graduated) {
        update['additionalInfo.graduated'] = true;
        graduates++;
      }
      transaction.update(snap.ref, update);

      entries.push({
        studentId: snap.id,
        name: `${data.firstName ?? ''} ${data.lastName ?? ''}`.trim(),
        prevAccess: (data.access as Record<string, unknown> | undefined) ?? null,
        prevYearLevel,
        prevYearLevelSetForYear,
        prevGraduated,
        bumped: ladder.changed && ladder.next != null,
        markedYearLevelForYear: ladder.changed && ladder.next != null,
        graduated: ladder.graduated,
      });
    }

    if (entries.length > 0) {
      transaction.create(renewalRef, {
        academicYear,
        status: 'applied',
        count: entries.length,
        performedBy: grantedBy,
        performedByName: grantedByName ?? null,
        performedAt: FieldValue.serverTimestamp(),
        entries,
      });
    }
    return {
      renewed: entries.length,
      graduates,
      skipped,
      batchId: entries.length > 0 ? renewalRef.id : null,
    };
  });

  return transactionResult;
}

/** Most-recent renewal batches for the undo list. */
export async function getRecentRenewalBatches(
  schoolId: string,
  max = 8
): Promise<RenewalBatchSummary[]> {
  const snap = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('renewalBatches')
    .orderBy('performedAt', 'desc')
    .limit(max)
    .get();

  return snap.docs.map((doc) => {
    const x = doc.data();
    const performedAt = x.performedAt as { toDate?: () => Date } | undefined;
    const undoneAt = x.undoneAt as { toDate?: () => Date } | undefined;
    return {
      id: doc.id,
      academicYear: (x.academicYear as number) ?? 0,
      count:
        (x.count as number) ?? (Array.isArray(x.entries) ? x.entries.length : 0),
      status: (x.status as 'applied' | 'undone') ?? 'applied',
      performedByName: (x.performedByName as string | null) ?? null,
      performedAtIso: performedAt?.toDate ? performedAt.toDate().toISOString() : null,
      undoneAtIso: undoneAt?.toDate ? undoneAt.toDate().toISOString() : null,
    };
  });
}

/**
 * Undo a renewal batch: restore each student's pre-renewal access, year level,
 * and graduated flag from the stored snapshot, then mark the batch undone.
 * Idempotent — a batch can only be undone once. Students deleted since the
 * renewal are skipped. Chunked into batches of 400.
 */
export async function undoRenewalBatch(
  schoolId: string,
  batchId: string,
  undoneBy: string
): Promise<{ reverted: number }> {
  const batchRef = adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('renewalBatches')
    .doc(batchId);
  const snap = await batchRef.get();
  if (!snap.exists) throw new Error('Renewal not found.');
  const data = snap.data()!;
  if (data.status !== 'applied') {
    throw new Error('This renewal has already been undone.');
  }
  const entries = (data.entries ?? []) as RenewalBatchEntry[];
  const studentsCol = adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('students');

  let reverted = 0;
  for (let i = 0; i < entries.length; i += 400) {
    const chunk = entries.slice(i, i + 400);
    const snaps = await adminDb.getAll(...chunk.map((e) => studentsCol.doc(e.studentId)));
    const present = new Set(snaps.filter((s) => s.exists).map((s) => s.id));
    const wb = adminDb.batch();
    for (const e of chunk) {
      if (!present.has(e.studentId)) continue; // deleted since renewal — skip
      const update: Record<string, unknown> = {
        access: e.prevAccess ?? FieldValue.delete(),
      };
      if (e.bumped) {
        update['additionalInfo.yearLevel'] = e.prevYearLevel ?? FieldValue.delete();
      }
      if (e.markedYearLevelForYear) {
        update['additionalInfo.yearLevelSetForYear'] =
          e.prevYearLevelSetForYear ?? FieldValue.delete();
      }
      if (e.graduated) {
        update['additionalInfo.graduated'] = e.prevGraduated ? true : FieldValue.delete();
      }
      wb.update(studentsCol.doc(e.studentId), update);
      reverted++;
    }
    await wb.commit();
  }

  await batchRef.update({
    status: 'undone',
    undoneBy,
    undoneAt: FieldValue.serverTimestamp(),
  });
  return { reverted };
}
