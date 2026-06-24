import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {
  buildSchoolAccess,
  buildStudentAccess,
  hardExpiryFor,
  isActiveSubscriptionStatus,
  nextYearLevel,
  DEFAULT_TIMEZONE,
  ROLLOVER_DAY,
} from "./access";

const fns = functions.region("australia-southeast1");

const STUDENT_BATCH = 400;

function db(): admin.firestore.Firestore {
  return admin.firestore();
}

function asNonEmptyString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      `${field} must be a non-empty string.`,
    );
  }
  return value.trim();
}

/** Caller must be a teacher or school admin of the target school. */
async function callerIsStaff(uid: string, schoolId: string): Promise<boolean> {
  const snap = await db()
    .collection("schools").doc(schoolId)
    .collection("users").doc(uid)
    .get();
  if (!snap.exists) return false;
  const role = (snap.data()?.role as string | undefined) ?? "";
  return role === "teacher" || role === "schoolAdmin";
}

/** Whether the school's subscription for `year` grants active access. */
async function schoolSubActive(
  schoolId: string,
  year: number,
): Promise<boolean> {
  const sub = await db()
    .collection("schoolSubscriptions")
    .doc(`${schoolId}_${year}`)
    .get();
  return sub.exists && isActiveSubscriptionStatus(sub.data()?.status as string);
}

// ─────────────────────────────────────────────────────────────────────────────
// T2 — renewStudents callable
// ─────────────────────────────────────────────────────────────────────────────

interface RenewInput {
  schoolId?: unknown;
  academicYear?: unknown;
  studentIds?: unknown;
}

/**
 * Carry a school's selected students into a new academic year. Sets each
 * student's `access` for `academicYear` (source: school_renewal), bumps the
 * recognised year level by one, and flags graduates. Requires the caller to be
 * staff at the school AND the school's subscription for that year to be active —
 * a school must both pay and select to renew (fail-closed by construction).
 */
export const renewStudents = fns
  .runWith({timeoutSeconds: 120, memory: "256MB"})
  .https.onCall(async (data: RenewInput, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Sign-in required.",
      );
    }
    const uid = context.auth.uid;
    const schoolId = asNonEmptyString(data.schoolId, "schoolId");
    const academicYear = Number(data.academicYear);
    if (!Number.isInteger(academicYear)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "academicYear must be an integer.",
      );
    }
    if (!Array.isArray(data.studentIds) || data.studentIds.length === 0) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "studentIds must be a non-empty array.",
      );
    }
    const studentIds = data.studentIds.map((s) => asNonEmptyString(s, "studentId"));

    if (!(await callerIsStaff(uid, schoolId))) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Only school staff may renew students.",
      );
    }
    if (!(await schoolSubActive(schoolId, academicYear))) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "School subscription is not active for that year.",
      );
    }

    const studentsCol = db()
      .collection("schools").doc(schoolId)
      .collection("students");

    let renewed = 0;
    let graduates = 0;
    for (let i = 0; i < studentIds.length; i += STUDENT_BATCH) {
      const chunk = studentIds.slice(i, i + STUDENT_BATCH);
      const snaps = await db().getAll(...chunk.map((id) => studentsCol.doc(id)));
      const batch = db().batch();
      for (const snap of snaps) {
        if (!snap.exists) continue;
        const additional = (snap.data()?.additionalInfo ?? {}) as Record<string, unknown>;
        const ladder = nextYearLevel(additional.yearLevel as string | undefined);

        const access = buildStudentAccess({
          academicYear,
          source: "school_renewal",
          grantedBy: uid,
        });

        const update: admin.firestore.UpdateData<admin.firestore.DocumentData> = {access};
        if (ladder.changed && ladder.next != null) {
          update["additionalInfo.yearLevel"] = ladder.next;
        }
        if (ladder.graduated) {
          update["additionalInfo.graduated"] = true;
          graduates++;
        }
        batch.update(snap.ref, update);
        renewed++;
      }
      await batch.commit();
    }

    functions.logger.info(
      `renewStudents: school ${schoolId} year ${academicYear} -> ` +
      `renewed ${renewed}, ${graduates} graduate(s) flagged.`,
    );
    return {renewed, graduates, academicYear};
  });

// ─────────────────────────────────────────────────────────────────────────────
// T4 — annualRollover scheduled cron (~25 Jan, Australia/Sydney)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Advance the global academic year and reconcile access. Modelled on
 * cleanupExpiredLinkCodes. Idempotent: if config already points at the new
 * year, it no-ops. Steps:
 *   1. advance config.currentAcademicYear (+ hardExpiry / rolloverDate)
 *   2. per school: set school.access from the new-year subscription (suspends
 *      unpaid schools), and cascade suspension onto renewed students
 *   3. expire the just-ended cohort (access.academicYear == prior year, still
 *      active) that was not renewed into the new year
 *
 * The absolute `access.expiresAt` is the backstop — even if this never runs,
 * access lapses on schedule. This job is the tidy-up + whole-school reconcile.
 */
export const annualRollover = fns.pubsub
  .schedule(`0 2 ${ROLLOVER_DAY} 1 *`) // 02:00 on 25 January
  .timeZone(DEFAULT_TIMEZONE)
  .onRun(async () => {
    const cfgRef = db().collection("config").doc("academicYear");
    const cfgSnap = await cfgRef.get();
    const priorYear = (cfgSnap.data()?.currentAcademicYear as number | undefined);
    if (typeof priorYear !== "number") {
      functions.logger.error("annualRollover: config/academicYear missing; aborting.");
      return null;
    }
    const newYear = priorYear + 1;

    // 1. Advance the global boundary.
    await cfgRef.set(
      {
        currentAcademicYear: newYear,
        rolloverDate: `${newYear + 1}-01-${ROLLOVER_DAY}`,
        hardExpiry: hardExpiryFor(newYear, DEFAULT_TIMEZONE).toISOString(),
        timezone: DEFAULT_TIMEZONE,
      },
      {merge: true},
    );

    const schools = await db().collection("schools").get();
    let suspendedSchools = 0;
    let expiredStudents = 0;

    for (const schoolDoc of schools.docs) {
      if (schoolDoc.data()?.isActive === false) continue;
      const schoolId = schoolDoc.id;
      const active = await schoolSubActive(schoolId, newYear);

      // 2. Whole-school access for the new year.
      await schoolDoc.ref.set(
        {
          access: buildSchoolAccess({
            status: active ? "active" : "suspended",
            academicYear: newYear,
            reason: active ? "rollover:paid" : "rollover:unpaid",
          }),
        },
        {merge: true},
      );
      if (!active) suspendedSchools++;

      // If the school is unpaid, suspend any students already renewed into the
      // new year (they were optimistically renewed before payment lapsed).
      if (!active) {
        expiredStudents += await flipStudents(
          schoolId,
          {academicYear: newYear, status: "active"},
          {"access.status": "suspended"},
        );
      }

      // 3. Expire the just-ended cohort that wasn't renewed forward.
      expiredStudents += await flipStudents(
        schoolId,
        {academicYear: priorYear, status: "active"},
        {"access.status": "expired"},
      );
    }

    functions.logger.info(
      `annualRollover: advanced ${priorYear} -> ${newYear}; ` +
      `suspended ${suspendedSchools} unpaid school(s); ` +
      `expired/suspended ${expiredStudents} student(s).`,
    );
    return null;
  });

/**
 * Apply `update` to every student in `schoolId` whose access matches the given
 * academicYear + status. Returns the count updated. Uses the
 * access.academicYear + access.status composite index.
 */
async function flipStudents(
  schoolId: string,
  match: {academicYear: number; status: string},
  update: admin.firestore.UpdateData<admin.firestore.DocumentData>,
): Promise<number> {
  const snap = await db()
    .collection("schools").doc(schoolId)
    .collection("students")
    .where("access.academicYear", "==", match.academicYear)
    .where("access.status", "==", match.status)
    .get();
  if (snap.empty) return 0;

  let count = 0;
  for (let i = 0; i < snap.docs.length; i += STUDENT_BATCH) {
    const chunk = snap.docs.slice(i, i + STUDENT_BATCH);
    const batch = db().batch();
    for (const doc of chunk) {
      batch.update(doc.ref, update);
      count++;
    }
    await batch.commit();
  }
  return count;
}
