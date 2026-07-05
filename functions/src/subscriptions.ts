import * as functions from "firebase-functions/v1";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import {
  buildSchoolAccess,
  isActiveSubscriptionStatus,
} from "./access";

const STUDENT_BATCH = 400;

function db(): admin.firestore.Firestore {
  return admin.firestore();
}

/**
 * The academic year currently in session — config/academicYear is the single
 * source of truth. Returns null if unset (caller then skips the cascade rather
 * than guessing).
 */
async function currentAcademicYear(): Promise<number | null> {
  const cfg = await db().collection("config").doc("academicYear").get();
  const v = cfg.data()?.currentAcademicYear;
  return typeof v === "number" ? v : null;
}

/**
 * Cascade a school's access verdict onto its students for one academic year.
 * - suspend: flip every student whose access is for `year` and currently
 *   `active` to `suspended`.
 * - restore: flip every student whose access is for `year` and currently
 *   `suspended` back to `active`.
 * Deliberately does NOT grant access to students who were never renewed — a
 * school paying late restores only the cohort the school had already selected.
 * @param {string} schoolId The school ID.
 * @param {number} year The academic year.
 * @param {boolean} active Whether the subscription grants active access.
 * @return {Promise<number>} The number of student docs updated.
 */
async function cascadeStudentAccess(
  schoolId: string,
  year: number,
  active: boolean,
): Promise<number> {
  const fromStatus = active ? "suspended" : "active";
  const toStatus = active ? "active" : "suspended";

  const snap = await db()
    .collection("schools").doc(schoolId)
    .collection("students")
    .where("access.academicYear", "==", year)
    .where("access.status", "==", fromStatus)
    .get();

  if (snap.empty) return 0;

  let updated = 0;
  for (let i = 0; i < snap.docs.length; i += STUDENT_BATCH) {
    const chunk = snap.docs.slice(i, i + STUDENT_BATCH);
    const batch = db().batch();
    for (const doc of chunk) {
      batch.update(doc.ref, {
        "access.status": toStatus,
      });
      updated++;
    }
    await batch.commit();
  }
  return updated;
}

/**
 * T1 — react to a `schoolSubscriptions/{schoolId}_{year}` write. Recompute the
 * school's `access` map and cascade suspend/restore to its students. Only acts
 * on the year currently in session, so editing a historical row can never
 * suspend a live school.
 */
export const onSchoolSubscriptionWrite = onDocumentWritten(
  {document: "schoolSubscriptions/{subId}", concurrency: 1},
  async (event) => {
    if (!event.data) return;
    const after = event.data.after.exists ? event.data.after.data() : null;
    if (!after) {
      // Row deleted — leave materialised access as-is; suspension is an
      // explicit action, not a side effect of cleanup.
      return;
    }

    const schoolId = after.schoolId as string | undefined;
    const year = after.academicYear as number | undefined;
    const status = after.status as string | undefined;
    if (!schoolId || typeof year !== "number" || !status) {
      functions.logger.warn("onSchoolSubscriptionWrite: malformed row", {
        subId: event.params.subId,
      });
      return;
    }

    const liveYear = await currentAcademicYear();
    if (liveYear !== null && year !== liveYear) {
      functions.logger.info(
        `onSchoolSubscriptionWrite: row year ${year} != live year ${liveYear}; ` +
        "skipping cascade.",
      );
      return;
    }

    const active = isActiveSubscriptionStatus(status);

    // Skip if nothing material changed (status active/inactive unchanged).
    const before = event.data.before.exists ? event.data.before.data() : null;
    if (before) {
      const wasActive = isActiveSubscriptionStatus(before.status as string);
      if (wasActive === active && before.academicYear === year) {
        return;
      }
    }

    const schoolAccess = buildSchoolAccess({
      status: active ? "active" : "suspended",
      academicYear: year,
      reason: `subscription:${status}`,
    });

    await db().collection("schools").doc(schoolId).set(
      {access: schoolAccess},
      {merge: true},
    );

    const cascaded = await cascadeStudentAccess(schoolId, year, active);
    functions.logger.info(
      `onSchoolSubscriptionWrite: school ${schoolId} year ${year} -> ` +
      `${active ? "active" : "suspended"}; cascaded ${cascaded} student(s).`,
    );
    return;
  });
