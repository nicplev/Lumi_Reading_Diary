import * as functions from "firebase-functions/v1";
import {onDocumentDeleted} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import {deleteAiEvalArtifacts, deleteStorageFile, Counts} from "./deletion";
import {isValidOccurredOn} from "./dateUtils";
import {errorCodeForLog} from "./log_safety";

/**
 * Dependent-data cascade for a single reading-log delete
 * (docs/PARENT_LOGGING_FLOW_PLAN.md §6.3, gap G9).
 *
 * A raw `readingLogs/{logId}.delete()` — parent undo / remove-my-session,
 * the legacy widget-undo banner, or a school-admin delete — previously
 * orphaned everything hanging off the log:
 *  - the `comments` subcollection (parent↔teacher thread),
 *  - both Storage audio objects (canonical + pending upload),
 *  - the AI comprehension eval doc and its pipeline job,
 *  - the day's home quick slot when this log held it.
 *
 * The whole-student cascade in deletion.ts cleans these itself before
 * deleting each log (and `recursiveDelete(studentRef)` removes quickSlots),
 * so this trigger skips when the student is pending deletion or already
 * gone. Every step is idempotent — at-least-once delivery and the overlap
 * with the student cascade are both safe.
 * @param {string} schoolId Owning school document ID.
 * @param {string} logId Deleted reading-log document ID.
 * @param {FirebaseFirestore.DocumentData | undefined} logData The deleted
 *   document's last data (from the delete event snapshot).
 * @return {Promise<Counts>} Cleanup counters (for logging/tests).
 */
export async function cleanupDeletedReadingLog(
  schoolId: string,
  logId: string,
  logData: FirebaseFirestore.DocumentData | undefined,
): Promise<Counts> {
  const db = admin.firestore();
  const counts: Counts = {};

  const studentId =
    typeof logData?.studentId === "string" ? logData.studentId : null;
  if (studentId) {
    const student =
      await db.doc(`schools/${schoolId}/students/${studentId}`).get();
    if (!student.exists || student.data()?.pendingDeletion === true) {
      counts.skippedStudentCascade = 1;
      return counts;
    }
  }

  await deleteStorageFile(
    `schools/${schoolId}/comprehension_audio/${logId}.m4a`,
    counts,
  );
  await deleteStorageFile(
    `comprehension_audio_uploads/${schoolId}/${logId}.m4a`,
    counts,
  );
  await deleteAiEvalArtifacts(schoolId, logId, counts);

  await db.recursiveDelete(
    db.collection(`schools/${schoolId}/readingLogs/${logId}/comments`));
  counts.commentThreadsCleared = 1;

  // Free the home quick slot if this log held it. Slot-holding logs always
  // carry occurredOn (rules pin slotDate == log.occurredOn at creation), so
  // no timezone derivation is needed; the logId match keeps a same-day
  // sibling's slot untouched.
  const occurredOn = logData?.occurredOn;
  if (studentId && isValidOccurredOn(occurredOn)) {
    const slotRef = db.doc(
      `schools/${schoolId}/students/${studentId}/quickSlots/${occurredOn}`);
    const slot = await slotRef.get();
    if (slot.exists && slot.data()?.logId === logId) {
      await slotRef.delete();
      counts.quickSlotsFreed = 1;
    }
  }

  return counts;
}

export const onReadingLogDeleted = onDocumentDeleted(
  {document: "schools/{schoolId}/readingLogs/{logId}", retry: true},
  async (event) => {
    try {
      const counts = await cleanupDeletedReadingLog(
        event.params.schoolId, event.params.logId, event.data?.data());
      // Counters only — no identifiers (log_safety guardrail).
      functions.logger.info("reading_log_cleanup", {...counts});
    } catch (error) {
      functions.logger.error("reading_log_cleanup_failed", {
        errorCode: errorCodeForLog(error),
      });
      throw error;
    }
  });
