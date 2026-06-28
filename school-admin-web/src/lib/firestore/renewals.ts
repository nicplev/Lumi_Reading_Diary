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
  /** Current materialised access status, if any (for the Status column). */
  accessStatus: 'active' | 'expired' | 'suspended' | null;
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
    const ladder = nextYearLevel(currentYearLevel);
    const accessYear = (d.access?.academicYear as number | undefined) ?? null;
    const accessStatus =
      (d.access?.status as 'active' | 'expired' | 'suspended' | undefined) ?? null;
    return {
      studentId: doc.id,
      firstName: d.firstName ?? '',
      lastName: d.lastName ?? '',
      classId,
      currentYearLevel,
      nextYearLevel: ladder.next,
      graduated: ladder.graduated,
      accessYear,
      accessStatus,
      alreadyRenewed: accessYear === targetAcademicYear,
    };
  });
}

export interface RenewResult {
  renewed: number;
  graduates: number;
  /** Id of the recorded batch (for an immediate undo); null if nothing renewed. */
  batchId: string | null;
}

/** Per-student before-snapshot captured at renewal, so a batch can be undone. */
export interface RenewalBatchEntry {
  studentId: string;
  name: string;
  prevAccess: Record<string, unknown> | null;
  prevYearLevel: string | null;
  prevGraduated: boolean;
  /** Whether this renewal bumped the year level (so undo knows to restore it). */
  bumped: boolean;
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
 * action can be undone (mistake recovery + audit trail). Mirrors the
 * renewStudents Cloud Function. Chunked into batches of 400.
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
  const entries: RenewalBatchEntry[] = [];
  let renewed = 0;
  let graduates = 0;

  for (let i = 0; i < studentIds.length; i += 400) {
    const chunk = studentIds.slice(i, i + 400);
    const snaps = await adminDb.getAll(...chunk.map((id) => studentsCol.doc(id)));
    const batch = adminDb.batch();
    for (const snap of snaps) {
      if (!snap.exists) continue;
      const data = snap.data() ?? {};
      const additional = (data.additionalInfo ?? {}) as Record<string, unknown>;
      const prevYearLevel = (additional.yearLevel as string | undefined) ?? null;
      const prevGraduated = additional.graduated === true;
      const ladder = nextYearLevel(prevYearLevel);

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

      entries.push({
        studentId: snap.id,
        name: `${data.firstName ?? ''} ${data.lastName ?? ''}`.trim(),
        prevAccess: (data.access as Record<string, unknown> | undefined) ?? null,
        prevYearLevel,
        prevGraduated,
        bumped: ladder.changed && ladder.next != null,
        graduated: ladder.graduated,
      });
      renewed++;
    }
    await batch.commit();
  }

  let batchId: string | null = null;
  if (entries.length > 0) {
    const ref = adminDb
      .collection('schools')
      .doc(schoolId)
      .collection('renewalBatches')
      .doc();
    await ref.set({
      academicYear,
      status: 'applied',
      count: entries.length,
      performedBy: grantedBy,
      performedByName: grantedByName ?? null,
      performedAt: FieldValue.serverTimestamp(),
      entries,
    });
    batchId = ref.id;
  }

  return { renewed, graduates, batchId };
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
