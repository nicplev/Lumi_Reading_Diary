import * as functions from "firebase-functions/v1";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import {
  academicYearForDate,
  buildStudentAccess,
  isActiveSubscriptionStatus,
} from "./access";

function db(): admin.firestore.Firestore {
  return admin.firestore();
}

/**
 * The academic year currently in session — `config/academicYear` is the single
 * source of truth. Falls back to deriving from "now" when the config doc is
 * missing (mirrors the parent-link grant path), so the very first school isn't
 * stranded before the config is seeded.
 * @return {Promise<number>} The academic year.
 */
async function currentAcademicYear(): Promise<number> {
  const cfg = await db().collection("config").doc("academicYear").get();
  const v = cfg.data()?.currentAcademicYear;
  return typeof v === "number" ? v : academicYearForDate(new Date());
}

/**
 * Grant access the moment a student is created, for schools on the
 * `whole_school_paid` access model with an active subscription. This closes the
 * "pre-link dead zone": under whole-school-paid every rostered student is
 * covered, but access was previously only materialised on parent-link,
 * subscription-activation provisioning, or bulk activation — so a student added
 * after those events (e.g. a mid-year transfer) had no `access` map and their
 * teacher couldn't log reading until a parent happened to link.
 *
 * Grant-only and idempotent: skips a student that already has an `access` map,
 * a school not on `whole_school_paid` (absent = whole_school_paid), or a school
 * whose subscription for the live year isn't active (those students get access
 * later via the subscription-activation cascade or the parent-link grant).
 * Composes with `onSchoolSubscriptionWrite` and the parent-link auto-grant,
 * which all skip students that already have live access.
 */
export const grantAccessOnStudentCreate = onDocumentCreated(
  "schools/{schoolId}/students/{studentId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const student = snap.data();

    // Already has an access map — nothing to do (idempotent).
    if (student.access) return;

    const {schoolId, studentId} = event.params;

    const schoolSnap = await db().collection("schools").doc(schoolId).get();
    if (!schoolSnap.exists) return;
    const accessMode = schoolSnap.data()?.accessMode ?? "whole_school_paid";
    if (accessMode !== "whole_school_paid") return;

    const year = await currentAcademicYear();

    const subSnap = await db()
      .collection("schoolSubscriptions")
      .doc(`${schoolId}_${year}`)
      .get();
    if (!subSnap.exists || !isActiveSubscriptionStatus(subSnap.data()?.status)) {
      // Not subscribed yet — provisioning on subscription activation (or the
      // parent-link grant) will cover this student later.
      return;
    }

    await snap.ref.set(
      {
        access: buildStudentAccess({
          academicYear: year,
          source: "book_pack_assumed",
          grantedBy: "system:whole_school_paid",
        }),
      },
      {merge: true},
    );

    functions.logger.info(
      `grantAccessOnStudentCreate: granted year ${year} access to ` +
        `student ${studentId} at whole-school-paid school ${schoolId}.`,
    );
  },
);
