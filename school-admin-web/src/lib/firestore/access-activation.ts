import { adminDb } from '@/lib/firebase/admin';
import { FieldValue } from 'firebase-admin/firestore';
import {
  DEFAULT_TIMEZONE,
  ROLLOVER_DAY,
  getCurrentAcademicYear,
  hardExpiryFor,
  isSchoolSubActive,
  isStudentAccessLive,
} from '@/lib/access';
import { isActiveSubscriptionStatus } from '@/lib/types';

/**
 * Self-serve access activation — the portal equivalent of the ops-only
 * `functions/scripts/backfill-access.cjs`, so a school admin can turn on
 * reading for a whole class without anyone running a terminal script (the
 * #1 Day-1 landmine: CSV-imported students carry no `access` map, so
 * fail-closed rules deny every parent's first log).
 *
 * Deliberately fail-closed on billing: it GRANTS student access for a year
 * whose school subscription is already active (mirroring the parent-link
 * auto-grant's `book_pack_assumed` source), but it never creates or changes a
 * subscription — that stays Lumi's decision. Idempotent and grant-only:
 * students already live are skipped, nobody is ever suspended.
 */

export interface AccessActivationResult {
  granted: number;
  /** Students already live, left untouched. */
  skipped: number;
  academicYear: number;
}

export type ManagedEnrollmentStatus =
  | 'book_pack'
  | 'direct_purchase'
  | 'not_enrolled';

export interface EnrollmentAccessUpdateResult {
  updated: number;
  skipped: number;
  academicYear: number;
  accessStatus: 'active' | 'revoked';
}

/**
 * Grant `book_pack_assumed` access for `academicYear` to every active student
 * whose access isn't already live. Requires the school subscription for that
 * year to be active (throws otherwise). Also ensures `config/academicYear`
 * exists and marks `school.access` active so the state is internally
 * consistent (sub → school → students). Chunked into 400-write batches.
 */
export async function activateAccessForYear(
  schoolId: string,
  academicYear: number,
  grantedBy: string
): Promise<AccessActivationResult> {
  if (!(await isSchoolSubActive(schoolId, academicYear))) {
    throw new SubscriptionInactiveError(academicYear);
  }

  const schoolRef = adminDb.collection('schools').doc(schoolId);
  const studentsCol = schoolRef.collection('students');
  const studentsSnap = await studentsCol.where('isActive', '==', true).get();

  const now = new Date();
  const expiresAt = hardExpiryFor(academicYear);
  const toGrant = studentsSnap.docs.filter(
    (d) =>
      d.data().access?.status !== 'revoked' &&
      !isStudentAccessLive(d.data().access, now)
  );

  for (let i = 0; i < toGrant.length; i += 400) {
    const chunk = toGrant.slice(i, i + 400);
    const batch = adminDb.batch();
    for (const doc of chunk) {
      batch.update(doc.ref, {
        access: {
          status: 'active',
          academicYear,
          expiresAt,
          source: 'book_pack_assumed',
          grantedAt: FieldValue.serverTimestamp(),
          grantedBy,
        },
      });
    }
    await batch.commit();
  }

  // Keep the school + config consistent with the grant (best-effort — the
  // student grants are what unblock logging; these just prevent later drift).
  await Promise.all([
    schoolRef
      .set(
        { access: { status: 'active', academicYear, updatedAt: FieldValue.serverTimestamp() } },
        { merge: true }
      )
      .catch(() => undefined),
    ensureAcademicYearConfig(academicYear).catch(() => undefined),
  ]);

  return {
    granted: toGrant.length,
    skipped: studentsSnap.size - toGrant.length,
    academicYear,
  };
}

/**
 * Grant access to a SINGLE student for the current year (used when an admin
 * marks a student subscribed). Same fail-closed subscription requirement,
 * same grant-only idempotence.
 */
export async function grantStudentAccessForCurrentYear(
  schoolId: string,
  studentId: string,
  grantedBy: string,
  source: 'book_pack_assumed' | 'parent_direct' = 'book_pack_assumed'
): Promise<{ granted: boolean; academicYear: number }> {
  const academicYear = await getCurrentAcademicYear();
  if (!(await isSchoolSubActive(schoolId, academicYear))) {
    throw new SubscriptionInactiveError(academicYear);
  }
  const ref = adminDb
    .collection('schools').doc(schoolId)
    .collection('students').doc(studentId);
  const snap = await ref.get();
  if (!snap.exists) return { granted: false, academicYear };
  if (snap.data()?.isActive === false) return { granted: false, academicYear };
  if (isStudentAccessLive(snap.data()?.access)) {
    return { granted: false, academicYear }; // already live — no-op
  }
  await ref.update({
    access: {
      status: 'active',
      academicYear,
      expiresAt: hardExpiryFor(academicYear),
      source,
      grantedAt: FieldValue.serverTimestamp(),
      grantedBy,
    },
  });
  return { granted: true, academicYear };
}

/**
 * Keep the portal's subscription label and the enforceable reading entitlement
 * in sync. Subscribed states grant current-year access; not_enrolled creates a
 * durable per-student `revoked` state that school subscription cascades and
 * bulk activation deliberately ignore. Student history and guardian links are
 * never touched.
 */
export async function updateStudentEnrollmentAndAccess(
  schoolId: string,
  studentIds: string[],
  enrollmentStatus: ManagedEnrollmentStatus,
  performedBy: string,
  reason?: string
): Promise<EnrollmentAccessUpdateResult> {
  const ids = Array.from(new Set(studentIds.map((id) => id.trim()).filter(Boolean)));
  if (ids.length === 0) {
    return {
      updated: 0,
      skipped: 0,
      academicYear: await getCurrentAcademicYear(),
      accessStatus: enrollmentStatus === 'not_enrolled' ? 'revoked' : 'active',
    };
  }

  const academicYear = await getCurrentAcademicYear();
  const revoking = enrollmentStatus === 'not_enrolled';
  if (ids.length > 400) {
    throw new Error('Access changes are limited to 400 students per audited batch.');
  }

  const studentsCol = adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('students');
  const refs = ids.map((id) => studentsCol.doc(id));
  const source =
    enrollmentStatus === 'direct_purchase' ? 'parent_direct' : 'book_pack_assumed';
  const revokeReason = reason?.trim() || 'Marked not subscribed by school admin';
  const auditRef = adminDb.collection('adminAuditLog').doc();

  // One transaction keeps the enforceable entitlement, subscription label,
  // and audit record in lock-step. For grants, reading the subscription inside
  // the transaction also closes the pay-status race with a concurrent lapse.
  const updated = await adminDb.runTransaction(async (transaction) => {
    if (!revoking) {
      const subscription = await transaction.get(
        adminDb.collection('schoolSubscriptions').doc(`${schoolId}_${academicYear}`)
      );
      if (
        !subscription.exists ||
        !isActiveSubscriptionStatus(subscription.data()?.status as string)
      ) {
        throw new SubscriptionInactiveError(academicYear);
      }
    }
    const snapshots = await Promise.all(refs.map((ref) => transaction.get(ref)));
    const targets = snapshots.filter(
      (snapshot) => snapshot.exists && snapshot.data()?.isActive !== false
    );
    for (const snapshot of targets) {
      const previousAccess =
        snapshot.data()?.access && typeof snapshot.data()?.access === 'object'
          ? snapshot.data()!.access
          : {};
      transaction.update(snapshot.ref, {
        enrollmentStatus,
        access: revoking
          ? {
              ...previousAccess,
              status: 'revoked',
              academicYear: previousAccess.academicYear ?? academicYear,
              expiresAt: previousAccess.expiresAt ?? hardExpiryFor(academicYear),
              revokedAt: FieldValue.serverTimestamp(),
              revokedBy: performedBy,
              revokeReason,
            }
          : {
              status: 'active',
              academicYear,
              expiresAt: hardExpiryFor(academicYear),
              source,
              grantedAt: FieldValue.serverTimestamp(),
              grantedBy: performedBy,
            },
      });
    }
    if (targets.length > 0) {
      transaction.create(auditRef, {
        action: revoking ? 'studentAccess.revoke' : 'studentAccess.grant',
        performedBy,
        targetType: targets.length === 1 ? 'student' : 'studentSelection',
        targetId: targets.length === 1 ? targets[0].id : schoolId,
        schoolId,
        metadata: {
          studentIds: targets.map((snapshot) => snapshot.id),
          enrollmentStatus,
          academicYear,
          reason: revoking ? revokeReason : null,
          count: targets.length,
        },
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    return targets.length;
  });

  return {
    updated,
    skipped: ids.length - updated,
    academicYear,
    accessStatus: revoking ? 'revoked' : 'active',
  };
}

/** Create `config/academicYear` if it is missing (never overwrites). */
async function ensureAcademicYearConfig(academicYear: number): Promise<void> {
  const ref = adminDb.collection('config').doc('academicYear');
  const snap = await ref.get();
  if (snap.exists && typeof snap.data()?.currentAcademicYear === 'number') return;
  const hardExpiry = hardExpiryFor(academicYear).toISOString();
  await ref.set(
    {
      currentAcademicYear: academicYear,
      rolloverDate: `${academicYear + 1}-01-${String(ROLLOVER_DAY).padStart(2, '0')}`,
      hardExpiry,
      timezone: DEFAULT_TIMEZONE,
    },
    { merge: true }
  );
}

/** Thrown when activation is attempted without an active school subscription. */
export class SubscriptionInactiveError extends Error {
  constructor(public academicYear: number) {
    super(
      `School subscription is not active for ${academicYear}. Contact Lumi to activate it.`
    );
    this.name = 'SubscriptionInactiveError';
  }
}
