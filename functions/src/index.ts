import * as functions from "firebase-functions";
import {defineSecret} from "firebase-functions/params";
import * as admin from "firebase-admin";
import sgMail from "@sendgrid/mail";

const sendgridApiKey = defineSecret("SENDGRID_API_KEY");
const sendgridSenderEmail = defineSecret("SENDGRID_SENDER_EMAIL");
import {
  isDueAt,
  isWithinQuietHours,
  mergeRecipientsByParent,
  NotificationAudienceType,
  normalizeNotificationPermissions,
  validateNotificationAudience,
} from "./notification_helpers";
import {buildOnboardingEmail, buildOnboardingQrAttachments} from "./email_templates";
import {
  computeGentleStreak,
  computeLongestStreak,
  countInWindow,
  localDateString,
} from "./dateUtils";

admin.initializeApp();
const db = admin.firestore();

// ─────────────────────────────────────────────────────────────────────────────
// Developer impersonation pipeline (read-only, fully-audited). See
// functions/src/impersonation.ts for the implementation. Re-exported so the
// Firebase CLI picks them up as deployable functions.
// ─────────────────────────────────────────────────────────────────────────────
export {
  startImpersonationSession,
  endImpersonationSession,
  revokeImpersonationSession,
  reportImpersonationActivity,
  reportBlockedWrite,
  exportImpersonationAudit,
  expireImpersonationSessions,
  revokeOnDevAccessRemoval,
  listImpersonableSchools,
  listImpersonableUsers,
  monitorImpersonationAnomalies,
} from "./impersonation";

// Parent ↔ student linking. Owns parents.linkedChildren and
// students.parentIds writes via Admin SDK so client rules can keep those
// fields locked down. See functions/src/parent_linking.ts.
export {
  linkParentToStudent,
  unlinkParentFromStudent,
} from "./parent_linking";

/**
 * CRITICAL SECURITY: Stats Aggregation
 * Prevents client-side manipulation of student statistics
 * Triggered on every reading log create, update, AND delete — the delete
 * path powers the widget-undo banner in the parent app, which deletes the
 * log doc and relies on this trigger to recompute the student's stats from
 * the remaining logs.
 */
export const aggregateStudentStats = functions.firestore
  .document("schools/{schoolId}/readingLogs/{logId}")
  .onWrite(async (change, context) => {
    const schoolId = context.params.schoolId;
    // On delete, change.after.exists is false; pull studentId from the
    // pre-delete snapshot so we still know which student's stats to recompute.
    const log = change.after.exists ? change.after.data() : change.before.data();

    if (!log) {
      functions.logger.warn("Reading log write event with no before or after data", {
        logId: context.params.logId,
      });
      return null;
    }

    const studentId = log.studentId;
    if (!studentId) {
      functions.logger.warn("Reading log has no studentId", {logId: context.params.logId});
      return null;
    }

    const studentRef = db.doc(`schools/${schoolId}/students/${studentId}`);

    try {
      // Get all reading logs for this student
      const logsSnapshot = await db
        .collection(`schools/${schoolId}/readingLogs`)
        .where("studentId", "==", studentId)
        .where("status", "in", ["completed", "partial"])
        .get();

      // Resolve the school's local day boundary so streaks and rolling windows
      // are bucketed by the family's calendar day, not UTC (mirrors
      // sendReadingReminders / getLocalTime). A 23:30 local log must count as
      // that night, not the next UTC day.
      const schoolSnap = await db.collection("schools").doc(schoolId).get();
      const tz = schoolSnap.data()?.timezone ?? "Europe/London";

      // Prior longestStreak — read so we can guarantee it never decreases
      // ("nothing earned is lost", even if the streak definition changes later).
      const priorLongest = (await studentRef.get()).data()?.stats?.longestStreak ?? 0;

      // Calculate stats from scratch (authoritative source).
      let totalMinutesRead = 0;
      let totalBooksRead = 0;
      let lastReadingDate: admin.firestore.Timestamp | null = null;
      // Unique local-day strings (YYYY-MM-DD in school tz) the student has read.
      const readingDates: Set<string> = new Set();

      logsSnapshot.docs.forEach((doc) => {
        const logData = doc.data();
        totalMinutesRead += logData.minutesRead || 0;
        totalBooksRead += (logData.bookTitles?.length || 0);

        if (logData.date) {
          const ts = logData.date as admin.firestore.Timestamp;
          readingDates.add(localDateString(ts.toDate(), tz));
          if (!lastReadingDate || ts.toMillis() > lastReadingDate.toMillis()) {
            lastReadingDate = ts;
          }
        }
      });

      const today = localDateString(new Date(), tz);

      // Gentle, forgiving streak: tolerates up to 2 missed days, computed fresh
      // from the local-day set. A missed night never resets it to zero on its
      // own — see computeGentleStreak in ./dateUtils.
      const {currentStreak, restDaysRemaining} = computeGentleStreak(readingDates, today);

      // Longest streak is monotonic — guard so it can never decrease.
      const longestStreak = Math.max(
        priorLongest,
        computeLongestStreak(readingDates),
        currentStreak,
      );

      const totalReadingDays = readingDates.size;
      const averageMinutesPerDay = totalReadingDays > 0 ? totalMinutesRead / totalReadingDays : 0;

      // Rolling "rhythm" windows — forgiving counts that slide instead of
      // resetting ("X of the last 30/50 nights").
      const last30DaysCount = countInWindow(readingDates, today, 30);
      const last50DaysCount = countInWindow(readingDates, today, 50);

      // Update student document with calculated stats (the single source of
      // truth — the client no longer persists computed stats).
      // NOTE: the legacy streakFreezes* fields are intentionally NOT written.
      // The earn/spend freeze economy is retired in favour of stateless
      // rest-day tolerance; old docs keep their values for back-compat reads but
      // they are now vestigial.
      await studentRef.update({
        "stats.totalMinutesRead": totalMinutesRead,
        "stats.totalBooksRead": totalBooksRead,
        "stats.currentStreak": currentStreak,
        "stats.longestStreak": longestStreak,
        "stats.lastReadingDate": lastReadingDate,
        "stats.averageMinutesPerDay": Math.round(averageMinutesPerDay * 10) / 10,
        "stats.totalReadingDays": totalReadingDays,
        "stats.last30DaysCount": last30DaysCount,
        "stats.last50DaysCount": last50DaysCount,
        "stats.restDaysRemaining": restDaysRemaining,
        "stats.lastUpdated": admin.firestore.FieldValue.serverTimestamp(),
      });

      functions.logger.info("Student stats aggregated", {
        studentId,
        totalMinutesRead,
        totalBooksRead,
        currentStreak,
      });

      return null;
    } catch (error) {
      functions.logger.error("Error aggregating student stats", {
        studentId,
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  });

// ---------------------------------------------------------------------------
// Reading reminders — scalable, cost-effective, per-parent scheduling
// ---------------------------------------------------------------------------

/** Max messages per sendEach call (FCM limit) */
const FCM_BATCH_LIMIT = 500;

/** How many schools to process concurrently (prevents OOM on large deployments) */
const SCHOOL_CONCURRENCY = 10;

/** Firestore `in` query limit */
const FIRESTORE_IN_LIMIT = 30;

type CampaignStatus = "queued" | "scheduled" | "processing" | "sent" | "partial" | "failed";

interface NotificationCampaignPayload {
  schoolId?: unknown;
  title?: unknown;
  body?: unknown;
  messageType?: unknown;
  audienceType?: unknown;
  classIds?: unknown;
  studentIds?: unknown;
  scheduledFor?: unknown;
}

interface NotificationCampaignData {
  schoolId: string;
  title: string;
  body: string;
  messageType: string;
  audienceType: NotificationAudienceType;
  targetClassIds: string[];
  targetStudentIds: string[];
  status: CampaignStatus;
  scheduledFor?: admin.firestore.Timestamp | null;
  createdAt?: admin.firestore.Timestamp | admin.firestore.FieldValue;
  sentAt?: admin.firestore.Timestamp | admin.firestore.FieldValue;
  createdBy: string;
  createdByRole: string;
  createdByName: string;
  recipientCounts?: {
    parents: number;
    students: number;
  };
  deliveryCounts?: {
    inboxWritten: number;
    pushSent: number;
    pushFailed: number;
  };
  errorSummary?: string | null;
}

interface CampaignStudentRecord {
  id: string;
  firstName: string;
  classId: string;
  parentIds: string[];
}

interface CampaignParentDelivery {
  parentId: string;
  parentRef: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>;
  token?: string;
  studentIds: string[];
  studentNames: string[];
  classIds: string[];
}

/**
 * Helper: resolve local hour & ISO weekday for a timezone.
 * @param {Date} utcNow - The current UTC time.
 * @param {string} tz - The IANA timezone string.
 * @return {{hour: number, weekday: number}} The local hour and ISO weekday.
 */
function getLocalTime(utcNow: Date, tz: string): {hour: number; weekday: number} {
  try {
    const hf = new Intl.DateTimeFormat("en-GB", {timeZone: tz, hour: "numeric", hour12: false});
    const hour = parseInt(hf.format(utcNow), 10);

    const df = new Intl.DateTimeFormat("en-GB", {timeZone: tz, weekday: "short"});
    const dayMap: Record<string, number> = {Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7};
    const weekday = dayMap[df.format(utcNow)] ?? 1;

    return {hour, weekday};
  } catch {
    const hour = utcNow.getUTCHours();
    const weekday = utcNow.getUTCDay() === 0 ? 7 : utcNow.getUTCDay();
    return {hour, weekday};
  }
}

/**
 * Helper: split array into chunks of `size`.
 * @param {Array} arr The array to chunk.
 * @param {number} size The chunk size.
 * @return {Array} The chunked array.
 */
function chunk<T>(arr: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < arr.length; i += size) {
    chunks.push(arr.slice(i, i + size));
  }
  return chunks;
}

/**
 * Helper: process an array with limited concurrency.
 * @param {T[]} items - Items to process.
 * @param {number} concurrency - Max concurrent operations.
 * @param {Function} fn - Async function to apply to each item.
 * @return {Promise<R[]>} The results.
 */
async function mapConcurrent<T, R>(
  items: T[],
  concurrency: number,
  fn: (item: T) => Promise<R>,
): Promise<R[]> {
  const results: R[] = [];
  const batches = chunk(items, concurrency);
  for (const batch of batches) {
    const batchResults = await Promise.all(batch.map(fn));
    results.push(...batchResults);
  }
  return results;
}

function asNonEmptyString(value: unknown, fieldName: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new functions.https.HttpsError("invalid-argument", `${fieldName} is required.`);
  }

  return value.trim();
}

function asOptionalTimestamp(value: unknown): admin.firestore.Timestamp | null {
  if (value == null) return null;

  if (typeof value === "number" && Number.isFinite(value)) {
    return admin.firestore.Timestamp.fromMillis(value);
  }

  if (typeof value === "string") {
    const millis = Date.parse(value);
    if (!Number.isNaN(millis)) {
      return admin.firestore.Timestamp.fromMillis(millis);
    }
  }

  if (typeof value === "object" && value !== null) {
    const maybeSeconds = (value as {seconds?: unknown}).seconds;
    if (typeof maybeSeconds === "number") {
      const nanoseconds = (value as {nanoseconds?: unknown}).nanoseconds;
      return new admin.firestore.Timestamp(
        maybeSeconds,
        typeof nanoseconds === "number" ? nanoseconds : 0,
      );
    }
  }

  throw new functions.https.HttpsError("invalid-argument", "scheduledFor must be a timestamp.");
}

function asStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return [...new Set(
    value
      .filter((item): item is string => typeof item === "string")
      .map((item) => item.trim())
      .filter((item) => item.length > 0),
  )];
}

function schoolRef(schoolId: string) {
  return db.collection("schools").doc(schoolId);
}

async function getTeacherAllowedClassIds(
  schoolId: string,
  userId: string,
): Promise<string[]> {
  const classesRef = schoolRef(schoolId).collection("classes");

  const [teacherIdsSnap, teacherIdSnap] = await Promise.all([
    classesRef.where("teacherIds", "array-contains", userId).get(),
    classesRef.where("teacherId", "==", userId).get(),
  ]);

  return [...new Set([
    ...teacherIdsSnap.docs.map((doc) => doc.id),
    ...teacherIdSnap.docs.map((doc) => doc.id),
  ])];
}

async function getStudentsByIds(
  schoolId: string,
  studentIds: string[],
): Promise<CampaignStudentRecord[]> {
  if (studentIds.length === 0) return [];

  const refs = studentIds.map((studentId) => schoolRef(schoolId).collection("students").doc(studentId));
  const docs = await db.getAll(...refs);
  return docs
    .filter((doc) => doc.exists)
    .map((doc) => {
      const data = doc.data() ?? {};
      return {
        id: doc.id,
        firstName: String(data.firstName ?? "Student"),
        classId: String(data.classId ?? ""),
        parentIds: Array.isArray(data.parentIds) ?
          data.parentIds.filter((id): id is string => typeof id === "string") :
          [],
        isActive: data.isActive !== false,
      };
    })
    .filter((student) => student.isActive)
    .map(({isActive, ...student}) => student); // eslint-disable-line @typescript-eslint/no-unused-vars
}

async function resolveCampaignStudents(
  schoolId: string,
  campaign: NotificationCampaignData,
): Promise<CampaignStudentRecord[]> {
  if (campaign.audienceType === "school") {
    const snap = await schoolRef(schoolId)
      .collection("students")
      .where("isActive", "==", true)
      .get();

    return snap.docs.map((doc) => {
      const data = doc.data();
      return {
        id: doc.id,
        firstName: String(data.firstName ?? "Student"),
        classId: String(data.classId ?? ""),
        parentIds: Array.isArray(data.parentIds) ?
          data.parentIds.filter((id): id is string => typeof id === "string") :
          [],
      };
    });
  }

  if (campaign.audienceType === "students") {
    return getStudentsByIds(schoolId, campaign.targetStudentIds);
  }

  const classRefs = campaign.targetClassIds.map(
    (classId) => schoolRef(schoolId).collection("classes").doc(classId),
  );
  const classDocs = classRefs.length > 0 ? await db.getAll(...classRefs) : [];
  const studentIds = new Set<string>();

  for (const classDoc of classDocs) {
    if (!classDoc.exists) continue;
    const data = classDoc.data() ?? {};
    if (data.isActive === false) continue;
    const classStudentIds = Array.isArray(data.studentIds) ?
      data.studentIds.filter((id): id is string => typeof id === "string") :
      [];
    classStudentIds.forEach((studentId) => studentIds.add(studentId));
  }

  return getStudentsByIds(schoolId, [...studentIds]);
}

async function buildParentDeliveries(
  schoolId: string,
  students: CampaignStudentRecord[],
): Promise<CampaignParentDelivery[]> {
  const mergedRecipients = mergeRecipientsByParent(students);
  if (mergedRecipients.length === 0) return [];

  const parentRefs = mergedRecipients.map(
    (recipient) => schoolRef(schoolId).collection("parents").doc(recipient.parentId),
  );
  const parentDocs = await db.getAll(...parentRefs);
  const parentDocMap = new Map(parentDocs.map((doc) => [doc.id, doc]));

  const deliveries: CampaignParentDelivery[] = [];

  for (const recipient of mergedRecipients) {
    const parentDoc = parentDocMap.get(recipient.parentId);
    if (!parentDoc?.exists) continue;

    const parentData = parentDoc.data() ?? {};
    if (parentData.isActive === false) continue;

    // Respect parent push notification preference
    const pushEnabled = parentData.preferences?.pushNotificationsEnabled !== false;

    deliveries.push({
      parentId: recipient.parentId,
      parentRef: parentDoc.ref,
      token: pushEnabled && typeof parentData.fcmToken === "string" ? parentData.fcmToken : undefined,
      studentIds: recipient.studentIds,
      studentNames: recipient.studentNames,
      classIds: recipient.classIds,
    });
  }

  return deliveries;
}

async function createParentInboxItems(
  deliveries: CampaignParentDelivery[],
  campaignId: string,
  campaign: NotificationCampaignData,
): Promise<void> {
  for (const batchDeliveries of chunk(deliveries, 400)) {
    const batch = db.batch();

    for (const delivery of batchDeliveries) {
      const notificationRef = delivery.parentRef.collection("notifications").doc(campaignId);
      batch.set(notificationRef, {
        campaignId,
        schoolId: campaign.schoolId,
        title: campaign.title,
        body: campaign.body,
        messageType: campaign.messageType,
        studentIds: delivery.studentIds,
        classIds: delivery.classIds,
        senderName: campaign.createdByName,
        senderRole: campaign.createdByRole,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
        pushStatus: delivery.token ? "pending" : "skipped_no_token",
        isRead: false,
        readAt: null,
      }, {merge: true});
    }

    await batch.commit();
  }
}

async function updateParentInboxStatuses(
  deliveries: CampaignParentDelivery[],
  campaignId: string,
  statusMap: Map<string, string>,
): Promise<void> {
  for (const batchDeliveries of chunk(deliveries, 400)) {
    const batch = db.batch();

    for (const delivery of batchDeliveries) {
      const status = statusMap.get(delivery.parentId);
      if (status == null) continue;
      const notificationRef = delivery.parentRef.collection("notifications").doc(campaignId);
      batch.update(notificationRef, {
        pushStatus: status,
      });
    }

    await batch.commit();
  }
}

async function dispatchNotificationCampaign(
  schoolId: string,
  campaignRef: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>,
): Promise<void> {
  const claimed = await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(campaignRef);
    if (!snap.exists) return false;

    const data = snap.data() as NotificationCampaignData;
    if (data.status !== "queued" && data.status !== "scheduled") {
      return false;
    }

    if (data.status === "scheduled" && !isDueAt(data.scheduledFor?.toMillis(), Date.now())) {
      return false;
    }

    transaction.update(campaignRef, {
      status: "processing",
      errorSummary: admin.firestore.FieldValue.delete(),
    });
    return true;
  });

  if (!claimed) return;

  const campaignSnap = await campaignRef.get();
  if (!campaignSnap.exists) return;

  try {
    const campaign = campaignSnap.data() as NotificationCampaignData;
    const students = await resolveCampaignStudents(schoolId, campaign);
    const deliveries = await buildParentDeliveries(schoolId, students);

    if (deliveries.length === 0) {
      await campaignRef.update({
        status: "failed",
        errorSummary: "No linked parents matched the selected audience.",
        recipientCounts: {
          parents: 0,
          students: students.length,
        },
        deliveryCounts: {
          inboxWritten: 0,
          pushSent: 0,
          pushFailed: 0,
        },
      });
      return;
    }

    await createParentInboxItems(deliveries, campaignRef.id, campaign);

    const statusByParentId = new Map<string, string>();
    const tokenMessages: admin.messaging.TokenMessage[] = [];
    const tokenOwners: string[] = [];
    const inboxWritten = deliveries.length;

    for (const delivery of deliveries) {
      if (!delivery.token) {
        statusByParentId.set(delivery.parentId, "skipped_no_token");
        continue;
      }

      tokenOwners.push(delivery.parentId);
      tokenMessages.push({
        token: delivery.token,
        notification: {
          title: campaign.title,
          body: campaign.body,
        },
        data: {
          type: "staff_message",
          campaignId: campaignRef.id,
          schoolId,
          messageType: campaign.messageType,
        },
        apns: {payload: {aps: {sound: "default"}}},
        android: {
          priority: "high" as const,
          notification: {sound: "default", clickAction: "FLUTTER_NOTIFICATION_CLICK"},
        },
      });
    }

    let pushSent = 0;
    let pushFailed = 0;
    const staleParentIds = new Set<string>();

    for (let i = 0; i < tokenMessages.length; i += FCM_BATCH_LIMIT) {
      const messageBatch = tokenMessages.slice(i, i + FCM_BATCH_LIMIT);
      const ownerBatch = tokenOwners.slice(i, i + FCM_BATCH_LIMIT);
      const result = await admin.messaging().sendEach(messageBatch);

      pushSent += result.successCount;
      pushFailed += result.failureCount;

      result.responses.forEach((response, index) => {
        const parentId = ownerBatch[index];
        if (response.success) {
          statusByParentId.set(parentId, "sent");
          return;
        }

        statusByParentId.set(parentId, "failed");
        const code = response.error?.code;
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token"
        ) {
          staleParentIds.add(parentId);
        }
      });
    }

    await updateParentInboxStatuses(deliveries, campaignRef.id, statusByParentId);

    if (staleParentIds.size > 0) {
      for (const batchParentIds of chunk([...staleParentIds], 400)) {
        const batch = db.batch();
        for (const parentId of batchParentIds) {
          batch.update(schoolRef(schoolId).collection("parents").doc(parentId), {
            fcmToken: admin.firestore.FieldValue.delete(),
            fcmTokenUpdatedAt: admin.firestore.FieldValue.delete(),
          });
        }
        await batch.commit();
      }
    }

    const skippedCount = [...statusByParentId.values()].filter((s) => s === "skipped_no_token").length;
    // Only mark as "partial" if there were actual push delivery failures.
    // Parents without tokens still receive inbox items — that's not a failure.
    const finalStatus: CampaignStatus = pushFailed > 0 ? "partial" : "sent";
    let errorSummary: string | null = null;
    if (pushFailed > 0 && skippedCount > 0) {
      errorSummary = `${pushFailed} push(es) failed, ${skippedCount} parent(s) have no push token.`;
    } else if (pushFailed > 0) {
      errorSummary = `${pushFailed} push notification(s) could not be delivered.`;
    } else if (skippedCount > 0) {
      errorSummary = `${skippedCount} parent(s) will see this in-app only (no push token).`;
    }

    await campaignRef.update({
      status: finalStatus,
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
      recipientCounts: {
        parents: deliveries.length,
        students: students.length,
      },
      deliveryCounts: {
        inboxWritten,
        pushSent,
        pushFailed,
        pushSkipped: skippedCount,
      },
      errorSummary,
    });
  } catch (error) {
    await campaignRef.update({
      status: "failed",
      errorSummary: error instanceof Error ? error.message : String(error),
    });
    throw error;
  }
}

export const createNotificationCampaign = functions
  .runWith({timeoutSeconds: 60, memory: "256MB"})
  .https.onCall(async (rawData: NotificationCampaignPayload, context) => {
    const senderId = context.auth?.uid;
    if (!senderId) {
      throw new functions.https.HttpsError("unauthenticated", "You must be signed in.");
    }
    try {
      const schoolId = asNonEmptyString(rawData.schoolId, "schoolId");
      const title = asNonEmptyString(rawData.title, "title");
      const body = asNonEmptyString(rawData.body, "body");
      const messageType = asNonEmptyString(rawData.messageType ?? "general", "messageType");
      const audienceType = asNonEmptyString(rawData.audienceType, "audienceType") as NotificationAudienceType;
      const requestedClassIds = asStringArray(rawData.classIds);
      const requestedStudentIds = asStringArray(rawData.studentIds);
      const scheduledFor = asOptionalTimestamp(rawData.scheduledFor);

      if (!["students", "classes", "school"].includes(audienceType)) {
        throw new functions.https.HttpsError("invalid-argument", "Invalid audienceType.");
      }

      const targetClassIds = audienceType === "classes" ? requestedClassIds : [];
      const targetStudentIds = audienceType === "students" ? requestedStudentIds : [];

      if (title.length > 120) {
        throw new functions.https.HttpsError("invalid-argument", "title must be 120 characters or fewer.");
      }

      if (body.length > 1000) {
        throw new functions.https.HttpsError("invalid-argument", "body must be 1000 characters or fewer.");
      }

      if (scheduledFor && scheduledFor.toMillis() <= Date.now()) {
        throw new functions.https.HttpsError("invalid-argument", "scheduledFor must be in the future.");
      }

      const senderSnap = await schoolRef(schoolId).collection("users").doc(senderId).get();
      if (!senderSnap.exists) {
        throw new functions.https.HttpsError("permission-denied", "Only staff can create notification campaigns.");
      }

      const senderData = senderSnap.data() ?? {};
      const senderRole = String(senderData.role ?? "");
      const senderName = String(senderData.fullName ?? "Staff");

      let allowedClassIds: string[] = [];
      if (senderRole === "teacher") {
        allowedClassIds = await getTeacherAllowedClassIds(schoolId, senderId);
      }

      const studentDocs = audienceType === "students" ?
        await getStudentsByIds(schoolId, targetStudentIds) :
        [];

      const validation = validateNotificationAudience({
        role: senderRole,
        permissions: senderData.permissions,
        audienceType,
        allowedClassIds,
        targetClassIds,
        studentClassIds: studentDocs.map((student) => student.classId),
        scheduledForMs: scheduledFor?.toMillis() ?? null,
      });

      if (!validation.ok) {
        throw new functions.https.HttpsError("permission-denied", validation.reason ?? "Notification not allowed.");
      }

      if (audienceType === "classes") {
        const classDocRefs = targetClassIds.map(
          (classId) => schoolRef(schoolId).collection("classes").doc(classId),
        );
        const classDocs = classDocRefs.length > 0 ?
          await db.getAll(...classDocRefs) :
          [];
        const validClassCount = classDocs.filter((doc) => doc.exists && doc.data()?.isActive !== false).length;
        if (validClassCount === 0) {
          throw new functions.https.HttpsError("invalid-argument", "Select at least one active class.");
        }
      }

      if (audienceType === "students" && studentDocs.length === 0) {
        throw new functions.https.HttpsError("invalid-argument", "Select at least one active student.");
      }

      // Rate limit: max 10 campaigns per teacher per hour
      const oneHourAgo = admin.firestore.Timestamp.fromMillis(Date.now() - 3600000);
      const recentCampaigns = await schoolRef(schoolId)
        .collection("notificationCampaigns")
        .where("createdBy", "==", senderId)
        .where("createdAt", ">=", oneHourAgo)
        .count()
        .get();

      if (recentCampaigns.data().count >= 10) {
        throw new functions.https.HttpsError(
          "resource-exhausted",
          "You have sent too many notifications recently. Please wait before sending more.",
        );
      }

      const permissions = normalizeNotificationPermissions(senderRole, senderData.permissions);
      const campaignRef = schoolRef(schoolId).collection("notificationCampaigns").doc();
      const campaignStatus: CampaignStatus = scheduledFor ? "scheduled" : "queued";

      await campaignRef.set({
        schoolId,
        title,
        body,
        messageType,
        audienceType,
        targetClassIds,
        targetStudentIds,
        status: campaignStatus,
        scheduledFor: scheduledFor ?? null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdBy: senderId,
        createdByRole: senderRole,
        createdByName: senderName,
        recipientCounts: {
          parents: 0,
          students: audienceType === "students" ? studentDocs.length : 0,
        },
        deliveryCounts: {
          inboxWritten: 0,
          pushSent: 0,
          pushFailed: 0,
        },
        errorSummary: null,
        permissionsSnapshot: permissions,
      });

      return {
        campaignId: campaignRef.id,
        status: campaignStatus,
      };
    } catch (error) {
      if (error instanceof functions.https.HttpsError) throw error;
      console.error("createNotificationCampaign error:", error);
      throw new functions.https.HttpsError(
        "internal",
        error instanceof Error ? error.message : "An unexpected error occurred."
      );
    }
  });

export const processQueuedNotificationCampaign = functions.firestore
  .document("schools/{schoolId}/notificationCampaigns/{campaignId}")
  .onCreate(async (snapshot, context) => {
    const campaign = snapshot.data() as NotificationCampaignData;
    if (campaign.status !== "queued") {
      return null;
    }

    await dispatchNotificationCampaign(context.params.schoolId, snapshot.ref);
    return null;
  });

export const dispatchScheduledNotificationCampaigns = functions
  .runWith({timeoutSeconds: 300, memory: "512MB"})
  .pubsub.schedule("every 1 minutes")
  .timeZone("UTC")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();
    const dueCampaigns = await db
      .collectionGroup("notificationCampaigns")
      .where("status", "==", "scheduled")
      .where("scheduledFor", "<=", now)
      .get();

    await mapConcurrent(dueCampaigns.docs, 10, async (doc) => {
      const schoolDocRef = doc.ref.parent.parent;
      const schoolId = schoolDocRef?.id;
      if (!schoolId) return;

      const schoolSnap = await schoolDocRef.get();
      const schoolData = schoolSnap.data() ?? {};
      const timezone = String(schoolData.timezone ?? "UTC");
      if (isWithinQuietHours(new Date(), timezone, schoolData.quietHours)) {
        return;
      }

      await dispatchNotificationCampaign(schoolId, doc.ref);
    });

    return null;
  });

/**
 * Process reminders for a single school.
 *
 * Flow:
 *  1. Determine local hour/weekday from school timezone.
 *  2. Fetch parents with tokens — filter eligible in memory.
 *  3. Gather student IDs from eligible parents' linkedChildren (no full students read).
 *  4. Check which of those students logged today (batched `in` queries).
 *  5. Build ONE message per parent listing all un-logged children.
 *  6. Send via sendEach in 500-msg chunks.
 *  7. Clean up stale tokens.
 *
 * @param {string} schoolId - The school document ID.
 * @param {FirebaseFirestore.DocumentData} schoolData - The school document data.
 * @param {Date} utcNow - The current UTC time.
 * @return {Promise<{sent: number, failed: number, stale: number}>} Delivery stats.
 */
async function processSchool(
  schoolId: string,
  schoolData: FirebaseFirestore.DocumentData,
  utcNow: Date,
): Promise<{sent: number; failed: number; stale: number}> {
  const schoolTz = schoolData.timezone || "Europe/London";
  const {hour: localHour, weekday: localWeekday} = getLocalTime(utcNow, schoolTz);

  // Quiet hours check
  if (isWithinQuietHours(utcNow, schoolTz, schoolData.quietHours)) {
    return {sent: 0, failed: 0, stale: 0};
  }

  // ---- Step 1: Fetch parents who have a token ----
  const parentsSnap = await db
    .collection(`schools/${schoolId}/parents`)
    .where("fcmToken", "!=", null)
    .get();

  if (parentsSnap.empty) return {sent: 0, failed: 0, stale: 0};

  // ---- Step 2: Filter eligible parents in memory ----
  // Also collect ALL student IDs we need to check (from linkedChildren)
  interface EligibleParent {
    id: string;
    token: string;
    linkedChildren: string[]; // student IDs
  }

  const eligible: EligibleParent[] = [];
  const allStudentIds = new Set<string>();

  for (const pDoc of parentsSnap.docs) {
    const p = pDoc.data();
    if (!p.fcmToken) continue;
    if (p.preferences?.notificationsEnabled === false) continue;

    // Hour check (default 18 / 6 PM)
    let prefHour = 18;
    if (p.preferences?.reminderTime) {
      const parts = (p.preferences.reminderTime as string).split(":");
      prefHour = parseInt(parts[0], 10) || 18;
    }
    if (prefHour !== localHour) continue;

    // Day-of-week check (empty = every day)
    const days: number[] = p.preferences?.reminderDays ?? [];
    if (days.length > 0 && !days.includes(localWeekday)) continue;

    const children: string[] = p.linkedChildren ?? [];
    if (children.length === 0) continue;

    eligible.push({id: pDoc.id, token: p.fcmToken, linkedChildren: children});
    children.forEach((c) => allStudentIds.add(c));
  }

  if (eligible.length === 0) return {sent: 0, failed: 0, stale: 0};

  // ---- Step 3: Check which students logged today ----
  // Use batched `in` queries on readingLogs (max 30 per query)
  const today = new Date(utcNow);
  today.setHours(0, 0, 0, 0);
  const todayTs = admin.firestore.Timestamp.fromDate(today);

  const tomorrow = new Date(today);
  tomorrow.setDate(tomorrow.getDate() + 1);
  const tomorrowTs = admin.firestore.Timestamp.fromDate(tomorrow);

  const loggedToday = new Set<string>();
  const studentIdBatches = chunk([...allStudentIds], FIRESTORE_IN_LIMIT);

  await Promise.all(studentIdBatches.map(async (batch) => {
    const snap = await db
      .collection(`schools/${schoolId}/readingLogs`)
      .where("studentId", "in", batch)
      .where("date", ">=", todayTs)
      .where("date", "<", tomorrowTs)
      .select("studentId")
      .get();
    snap.docs.forEach((d) => loggedToday.add(d.data().studentId as string));
  }));

  // ---- Step 4: Fetch student first names for un-logged children ----
  // Only read student docs we actually need (children not yet logged)
  const unloggedIds = [...allStudentIds].filter((id) => !loggedToday.has(id));
  if (unloggedIds.length === 0) return {sent: 0, failed: 0, stale: 0};

  const studentNames = new Map<string, string>();
  const nameBatches = chunk(unloggedIds, FIRESTORE_IN_LIMIT);

  await Promise.all(nameBatches.map(async (batch) => {
    // getAll is more efficient than individual reads
    const refs = batch.map((id) => db.doc(`schools/${schoolId}/students/${id}`));
    const docs = await db.getAll(...refs);
    docs.forEach((d) => {
      if (d.exists) {
        studentNames.set(d.id, d.data()?.firstName ?? "your child");
      }
    });
  }));

  // ---- Step 5: Build ONE message per parent ----
  const messages: admin.messaging.TokenMessage[] = [];
  const msgParentIds: string[] = [];

  for (const parent of eligible) {
    const unloggedIds = parent.linkedChildren.filter(
      (id) => !loggedToday.has(id) && studentNames.has(id),
    );
    if (unloggedIds.length === 0) continue;
    const unloggedNames = unloggedIds.map((id) => studentNames.get(id) as string);

    // Build a human-readable body
    let body: string;
    if (unloggedNames.length === 1) {
      body = `Don't forget to log ${unloggedNames[0]}'s reading today!`;
    } else if (unloggedNames.length === 2) {
      body = `Don't forget to log ${unloggedNames[0]} and ${unloggedNames[1]}'s reading today!`;
    } else {
      const last = unloggedNames[unloggedNames.length - 1];
      const rest = unloggedNames.slice(0, -1).join(", ");
      body = `Don't forget to log ${rest} and ${last}'s reading today!`;
    }

    messages.push({
      token: parent.token,
      notification: {
        title: "Time to read with Lumi! 📚",
        body,
      },
      data: {
        type: "reading_reminder",
        schoolId,
        // Comma-joined because FCM data values must be strings. Lets a future
        // client-side tap handler route directly to the right child's log
        // screen without re-fetching state.
        studentIds: unloggedIds.join(","),
      },
      apns: {payload: {aps: {sound: "default"}}},
      android: {
        priority: "high" as const,
        notification: {sound: "default", clickAction: "FLUTTER_NOTIFICATION_CLICK"},
      },
    });
    msgParentIds.push(parent.id);
  }

  if (messages.length === 0) return {sent: 0, failed: 0, stale: 0};

  // ---- Step 6: Send in 500-message chunks ----
  let totalSent = 0;
  let totalFailed = 0;
  const staleParentIds = new Set<string>();

  const msgChunks = chunk(messages, FCM_BATCH_LIMIT);
  const idChunks = chunk(msgParentIds, FCM_BATCH_LIMIT);

  for (let i = 0; i < msgChunks.length; i++) {
    const results = await admin.messaging().sendEach(msgChunks[i]);
    totalSent += results.successCount;
    totalFailed += results.failureCount;

    results.responses.forEach((resp, idx) => {
      if (!resp.success && resp.error) {
        const code = resp.error.code;
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token"
        ) {
          staleParentIds.add(idChunks[i][idx]);
        }
      }
    });
  }

  // ---- Step 7: Clean up stale tokens ----
  if (staleParentIds.size > 0) {
    const staleBatches = chunk([...staleParentIds], 500); // Firestore batch limit
    for (const batch of staleBatches) {
      const writeBatch = db.batch();
      for (const pid of batch) {
        writeBatch.update(db.doc(`schools/${schoolId}/parents/${pid}`), {
          fcmToken: admin.firestore.FieldValue.delete(),
          fcmTokenUpdatedAt: admin.firestore.FieldValue.delete(),
        });
      }
      await writeBatch.commit();
    }
  }

  return {sent: totalSent, failed: totalFailed, stale: staleParentIds.size};
}

/**
 * Send reading reminder notifications to parents.
 *
 * Runs every hour. Uses school timezone to match each parent's preferred
 * reminder hour and day-of-week. One notification per parent (not per child).
 * Processes schools with bounded concurrency and sends FCM in 500-msg chunks.
 *
 * Firestore reads per school ≈ parents(with token) + unlogged_students + log_checks
 * (NOT all students × all logs like the naive approach)
 */
export const sendReadingReminders = functions
  .runWith({timeoutSeconds: 300, memory: "512MB"})
  .pubsub.schedule("0 * * * *") // Every hour on the hour
  .timeZone("UTC")
  .onRun(async () => {
    const utcNow = new Date();
    functions.logger.info("sendReadingReminders tick", {utcHour: utcNow.getUTCHours()});

    try {
      const schoolsSnap = await db.collection("schools").get();

      const results = await mapConcurrent(
        schoolsSnap.docs,
        SCHOOL_CONCURRENCY,
        (doc) => processSchool(doc.id, doc.data(), utcNow),
      );

      const totals = results.reduce(
        (acc, r) => ({sent: acc.sent + r.sent, failed: acc.failed + r.failed, stale: acc.stale + r.stale}),
        {sent: 0, failed: 0, stale: 0},
      );

      functions.logger.info("sendReadingReminders complete", {
        schools: schoolsSnap.size,
        ...totals,
      });

      return null;
    } catch (error) {
      functions.logger.error("Error in sendReadingReminders", {
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  });

// ─── Stale FCM token GC ──────────────────────────────────────────────────────

/** Days of inactivity before an FCM token is treated as abandoned. */
const FCM_TOKEN_STALE_DAYS = 30;

/**
 * Remove FCM tokens whose `fcmTokenUpdatedAt` is older than the cutoff.
 *
 * Tokens auto-refresh whenever the app opens (via NotificationService.onTokenRefresh
 * and saveTokenForUser), so a token that hasn't moved in {@link FCM_TOKEN_STALE_DAYS}
 * days is from a device the parent no longer uses. Leaving it in place keeps
 * `sendReadingReminders` issuing pushes that always fail — wasted reads/writes
 * and noise in delivery metrics.
 *
 * The per-send cleanup in `processSchool` only prunes tokens that FCM actively
 * rejects; this catches the long tail where the token is still technically
 * registered but the user has uninstalled or stopped opening the app.
 *
 * @param {string} schoolId
 * @param {FirebaseFirestore.Timestamp} cutoff
 * @return {Promise<number>} Number of parent documents whose token was deleted.
 */
async function pruneStaleTokensForSchool(
  schoolId: string,
  cutoff: FirebaseFirestore.Timestamp,
): Promise<number> {
  const parentsSnap = await db
    .collection(`schools/${schoolId}/parents`)
    .where("fcmTokenUpdatedAt", "<", cutoff)
    .get();

  if (parentsSnap.empty) return 0;

  let removed = 0;
  let batch = db.batch();
  let inBatch = 0;
  for (const doc of parentsSnap.docs) {
    if (!doc.data().fcmToken) continue;
    batch.update(doc.ref, {
      fcmToken: admin.firestore.FieldValue.delete(),
      fcmTokenUpdatedAt: admin.firestore.FieldValue.delete(),
    });
    inBatch++;
    removed++;
    if (inBatch >= 400) {
      await batch.commit();
      batch = db.batch();
      inBatch = 0;
    }
  }
  if (inBatch > 0) await batch.commit();

  return removed;
}

/**
 * Weekly sweep to drop FCM tokens that haven't refreshed in 30 days.
 * Runs Mondays at 04:00 UTC — off-peak across LON/NYC/SYD.
 */
export const pruneStaleFcmTokens = functions
  .runWith({timeoutSeconds: 540, memory: "512MB"})
  .pubsub.schedule("0 4 * * 1")
  .timeZone("UTC")
  .onRun(async () => {
    const cutoff = admin.firestore.Timestamp.fromMillis(
      Date.now() - FCM_TOKEN_STALE_DAYS * 24 * 60 * 60 * 1000,
    );
    functions.logger.info("pruneStaleFcmTokens tick", {
      cutoff: cutoff.toDate().toISOString(),
    });

    try {
      const schoolsSnap = await db.collection("schools").get();
      const results = await mapConcurrent(
        schoolsSnap.docs,
        SCHOOL_CONCURRENCY,
        (doc) => pruneStaleTokensForSchool(doc.id, cutoff),
      );
      const total = results.reduce((sum, r) => sum + r, 0);
      functions.logger.info("pruneStaleFcmTokens complete", {
        schools: schoolsSnap.size,
        removed: total,
      });
      return null;
    } catch (error) {
      functions.logger.error("Error in pruneStaleFcmTokens", {
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  });

// ─── Achievement system constants ────────────────────────────────────────────

// Keep in sync with AchievementThresholds.defaults in
// lib/data/models/achievement_model.dart. readingDays is the primary
// (cumulative "nights read") reward ladder; streak tiers are no longer awarded.
const DEFAULT_ACHIEVEMENT_THRESHOLDS = {
  streak: [5, 10, 20, 50, 100],
  books: [5, 10, 25, 50, 100],
  minutes: [300, 600, 1500, 3000, 6000],
  readingDays: [10, 50, 100, 365],
};

interface AchievementTierMeta {
  id: string;
  name: string;
  icon: string;
  category: string;
  rarity: string;
  requirementType: string;
  description: (value: number) => string;
}

// NOTE: streak tiers are intentionally NOT awarded. Streaks are a gentle,
// secondary signal that earns no rewards — cumulative "nights read" (DAYS_TIERS)
// is the reward ladder, so a missed night never costs a child a badge. Streak
// badges earned under the old system remain on student docs and still render.

/* eslint-disable max-len */
const BOOKS_TIERS: AchievementTierMeta[] = [
  {id: "books_t1", name: "Book Beginner", icon: "📖", category: "books", rarity: "common", requirementType: "books", description: (v) => `Read ${v} books!`},
  {id: "books_t2", name: "Book Collector", icon: "📚", category: "books", rarity: "uncommon", requirementType: "books", description: (v) => `Read ${v} books!`},
  {id: "books_t3", name: "Avid Reader", icon: "📗", category: "books", rarity: "rare", requirementType: "books", description: (v) => `Read ${v} books!`},
  {id: "books_t4", name: "Bookworm", icon: "🐛", category: "books", rarity: "epic", requirementType: "books", description: (v) => `Read ${v} books!`},
  {id: "books_t5", name: "Reading Legend", icon: "🏆", category: "books", rarity: "legendary", requirementType: "books", description: (v) => `Read ${v} books!`},
];

const MINUTES_TIERS: AchievementTierMeta[] = [
  {id: "minutes_t1", name: "Hour Hand", icon: "⏰", category: "minutes", rarity: "common", requirementType: "minutes", description: (v) => `Read for ${v / 60} hours total!`},
  {id: "minutes_t2", name: "Time Traveler", icon: "⌚", category: "minutes", rarity: "uncommon", requirementType: "minutes", description: (v) => `Read for ${v / 60} hours total!`},
  {id: "minutes_t3", name: "Marathon Reader", icon: "🏃", category: "minutes", rarity: "rare", requirementType: "minutes", description: (v) => `Read for ${v / 60} hours total!`},
  {id: "minutes_t4", name: "Time Master", icon: "⏳", category: "minutes", rarity: "epic", requirementType: "minutes", description: (v) => `Read for ${v / 60} hours total!`},
  {id: "minutes_t5", name: "Eternal Reader", icon: "♾️", category: "minutes", rarity: "legendary", requirementType: "minutes", description: (v) => `Read for ${v / 60} hours total!`},
];

// Cumulative "nights read" ladder — the primary reward track. Every night
// counts forever and is never lost. Thresholds: see DEFAULT_ACHIEVEMENT_THRESHOLDS
// (readingDays) and the mirror in achievement_model.dart.
const DAYS_TIERS: AchievementTierMeta[] = [
  {id: "days_t1", name: "Decade Reader", icon: "📅", category: "readingDays", rarity: "common", requirementType: "days", description: (v) => `Read on ${v} nights!`},
  {id: "days_t2", name: "Fifty Nights", icon: "🌙", category: "readingDays", rarity: "rare", requirementType: "days", description: (v) => `Read on ${v} nights!`},
  {id: "days_t3", name: "Century Reader", icon: "💯", category: "readingDays", rarity: "epic", requirementType: "days", description: (v) => `Read on ${v} nights!`},
  {id: "days_t4", name: "Year of Reading", icon: "🏆", category: "readingDays", rarity: "legendary", requirementType: "days", description: (v) => `Read on ${v} nights — a whole year!`},
];

/* eslint-enable max-len */
const FIRST_LOG_ACHIEVEMENT = {
  id: "first_log",
  name: "First Chapter",
  description: "Logged your very first reading session!",
  icon: "📖",
  category: "special",
  rarity: "common",
  requirementType: "days",
  requiredValue: 1,
};

/**
 * Achievement Detector
 * Triggers when student stats are updated to check for new achievements.
 * Reads school-level custom thresholds (falls back to defaults if not set).
 * Awards all 19 tier achievements + the first_log special achievement.
 */
export const detectAchievements = functions.firestore
  .document("schools/{schoolId}/students/{studentId}")
  .onUpdate(async (change, context) => {
    const schoolId = context.params.schoolId;
    const studentId = context.params.studentId;
    const newData = change.after.data();
    const oldData = change.before.data();

    const newStats = newData.stats || {};
    const oldStats = oldData.stats || {};

    // Load school-level custom thresholds, fall back to defaults per category
    let customThresholds: Record<string, number[]> = {};
    try {
      const schoolDoc = await db.collection("schools").doc(schoolId).get();
      customThresholds = schoolDoc.data()?.settings?.achievementThresholds ?? {};
    } catch (err) {
      functions.logger.warn("Could not load school achievement thresholds, using defaults", {schoolId, err});
    }

    const thresholds = {
      streak: (customThresholds.streak ?? DEFAULT_ACHIEVEMENT_THRESHOLDS.streak),
      books: (customThresholds.books ?? DEFAULT_ACHIEVEMENT_THRESHOLDS.books),
      minutes: (customThresholds.minutes ?? DEFAULT_ACHIEVEMENT_THRESHOLDS.minutes),
      readingDays: (customThresholds.readingDays ?? DEFAULT_ACHIEVEMENT_THRESHOLDS.readingDays),
    };

    // Build set of already-earned IDs to prevent duplicates
    const existingAchievements: Array<Record<string, unknown>> = newData.achievements || [];
    const earnedIds = new Set<string>(existingAchievements.map((a) => a.id as string));

    type NewAchievement = {
      id: string; name: string; description: string; icon: string;
      category: string; rarity: string; requirementType: string; requiredValue: number;
      earnedAt: admin.firestore.FieldValue;
    };
    const toAward: NewAchievement[] = [];

    // Helper: check a tier list against a stat
    function checkTiers(
      tiers: AchievementTierMeta[],
      tierThresholds: number[],
      newVal: number,
      oldVal: number,
    ) {
      for (let i = 0; i < tiers.length; i++) {
        const threshold = tierThresholds[i];
        if (threshold === undefined) continue;
        if (earnedIds.has(tiers[i].id)) continue;
        if (newVal >= threshold && oldVal < threshold) {
          toAward.push({
            ...tiers[i],
            description: tiers[i].description(threshold),
            requiredValue: threshold,
            earnedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      }
    }

    // Streaks deliberately award nothing (see DAYS_TIERS note above).
    checkTiers(BOOKS_TIERS, thresholds.books, newStats.totalBooksRead || 0, oldStats.totalBooksRead || 0);
    checkTiers(MINUTES_TIERS, thresholds.minutes, newStats.totalMinutesRead|| 0, oldStats.totalMinutesRead|| 0);
    checkTiers(DAYS_TIERS, thresholds.readingDays, newStats.totalReadingDays|| 0, oldStats.totalReadingDays|| 0);

    // First-log special achievement
    if (
      !earnedIds.has(FIRST_LOG_ACHIEVEMENT.id) &&
      (newStats.totalReadingDays || 0) >= 1 &&
      (oldStats.totalReadingDays || 0) === 0
    ) {
      toAward.push({
        ...FIRST_LOG_ACHIEVEMENT,
        earnedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    if (toAward.length === 0) return null;

    // Write all new achievements in a single update
    await change.after.ref.update({
      achievements: admin.firestore.FieldValue.arrayUnion(...toAward),
    });

    functions.logger.info("Achievements awarded", {studentId, schoolId, awarded: toAward.map((a) => a.id)});

    // Notify parents (single notification listing all new achievements)
    if (newData.parentIds?.length > 0) {
      const achievementNames = toAward.map((a) => a.name).join(", ");
      for (const parentId of newData.parentIds) {
        try {
          const parentDoc = await db.doc(`schools/${schoolId}/parents/${parentId}`).get();
          const fcmToken = parentDoc.data()?.fcmToken;
          if (!fcmToken) continue;

          await admin.messaging().send({
            token: fcmToken,
            notification: {
              title: `${newData.firstName} earned new achievements! 🎉`,
              body: achievementNames,
            },
            data: {
              type: "achievement_earned",
              studentId,
              schoolId,
              achievements: JSON.stringify(toAward.map(({id, name, icon}) => ({id, name, icon}))),
            },
          });
          functions.logger.info("Achievement notification sent", {parentId, studentId});
        } catch (error) {
          functions.logger.error("Failed to send achievement notification", {
            parentId,
            error: error instanceof Error ? error.message : String(error),
          });
        }
      }
    }

    return null;
  });

/**
 * Validate Reading Log
 * Server-side validation before allowing log creation
 */
export const validateReadingLog = functions.firestore
  .document("schools/{schoolId}/readingLogs/{logId}")
  .onCreate(async (snapshot, context) => {
    const schoolId = context.params.schoolId;
    const logData = snapshot.data();

    // Validation rules
    const validationErrors: string[] = [];

    // Validate minutes read (reasonable limits)
    if (logData.minutesRead < 1 || logData.minutesRead > 240) {
      validationErrors.push("Minutes read must be between 1 and 240");
    }

    // Validate student exists
    const studentDoc = await db
      .doc(`schools/${schoolId}/students/${logData.studentId}`)
      .get();

    if (!studentDoc.exists) {
      validationErrors.push("Student does not exist");
    }

    // Validate parent has permission
    const studentData = studentDoc.data();
    if (studentData && !studentData.parentIds?.includes(logData.parentId)) {
      validationErrors.push("Parent not linked to this student");
    }

    // If validation fails, mark the log as invalid
    if (validationErrors.length > 0) {
      await snapshot.ref.update({
        validationStatus: "invalid",
        validationErrors: validationErrors,
      });

      functions.logger.warn("Invalid reading log detected", {
        logId: context.params.logId,
        errors: validationErrors,
      });
    } else {
      await snapshot.ref.update({
        validationStatus: "valid",
        validatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    return null;
  });

/**
 * Clean up expired link codes
 * Runs daily to remove old codes
 */
export const cleanupExpiredLinkCodes = functions.pubsub
  .schedule("0 2 * * *") // 2 AM daily
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();

    try {
      const expiredCodesSnapshot = await db
        .collection("studentLinkCodes")
        .where("expiresAt", "<", now)
        .where("status", "==", "active")
        .get();

      const batch = db.batch();
      let count = 0;

      expiredCodesSnapshot.docs.forEach((doc) => {
        batch.update(doc.ref, {
          status: "expired",
          expiredAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        count++;
      });

      if (count > 0) {
        await batch.commit();
        functions.logger.info(`Expired ${count} link codes`);
      }

      return null;
    } catch (error) {
      functions.logger.error("Error cleaning up expired codes", {
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  });

/**
 * Update class statistics when allocations or logs change
 */
// ─── Parent Onboarding Emails ───────────────────────────────────────────

const LINK_CODE_CHARS = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const LINK_CODE_LENGTH = 8;
const LINK_CODE_EXPIRY_DAYS = 365;

function generateLinkCode(): string {
  let code = "";
  for (let i = 0; i < LINK_CODE_LENGTH; i++) {
    code += LINK_CODE_CHARS.charAt(
      Math.floor(Math.random() * LINK_CODE_CHARS.length)
    );
  }
  return code;
}

async function getOrCreateLinkCode(
  studentId: string,
  schoolId: string,
  createdBy: string,
  studentName: string,
): Promise<string> {
  // Check for existing active code
  const existing = await db
    .collection("studentLinkCodes")
    .where("studentId", "==", studentId)
    .where("status", "==", "active")
    .orderBy("createdAt", "desc")
    .limit(1)
    .get();

  if (!existing.empty) {
    return existing.docs[0].data().code as string;
  }

  // Generate a unique code
  let code = generateLinkCode();
  let attempts = 0;
  while (attempts < 40) {
    const dup = await db
      .collection("studentLinkCodes")
      .where("code", "==", code)
      .limit(1)
      .get();
    if (dup.empty) break;
    code = generateLinkCode();
    attempts++;
  }

  const now = admin.firestore.Timestamp.now();
  const expiresAt = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + LINK_CODE_EXPIRY_DAYS * 24 * 60 * 60 * 1000)
  );

  await db.collection("studentLinkCodes").add({
    code,
    studentId,
    schoolId,
    status: "active",
    createdAt: now,
    expiresAt,
    createdBy,
    metadata: {studentFullName: studentName},
  });

  return code;
}

interface OnboardingEmailRecipient {
  studentId: string;
  studentName: string;
  parentEmail: string;
  linkCode: string;
  status: "sent" | "failed" | "skipped";
  error?: string;
  skippedReason?: string;
}

export const processParentOnboardingEmail = functions
  .runWith({timeoutSeconds: 120, memory: "512MB", secrets: [sendgridApiKey, sendgridSenderEmail]})
  .firestore.document("schools/{schoolId}/parentOnboardingEmails/{emailId}")
  .onCreate(async (snapshot, context) => {
    const data = snapshot.data();
    if (data.status !== "queued") return null;

    const schoolId = context.params.schoolId;
    const docRef = snapshot.ref;

    // Claim the document
    await docRef.update({status: "processing"});

    try {
      // Initialize SendGrid
      const sendgridKey = sendgridApiKey.value();
      if (!sendgridKey) {
        await docRef.update({
          status: "failed",
          errorSummary: "SendGrid API key not configured",
        });
        return null;
      }
      sgMail.setApiKey(sendgridKey);

      // Fetch school
      const schoolSnap = await db.doc(`schools/${schoolId}`).get();
      const schoolName = schoolSnap.data()?.name ?? "Your School";

      const targetStudentIds: string[] = data.targetStudentIds ?? [];
      const customMessage: string | undefined = data.customMessage;
      const emailSubject = data.emailSubject ?? `Welcome to Lumi Reading Tracker - ${schoolName}`;
      const generateMissingCodes = data.generateMissingCodes !== false;
      const createdBy: string = data.createdBy ?? "";

      // Fetch students in batches
      const recipients: OnboardingEmailRecipient[] = [];

      for (const studentBatch of chunk(targetStudentIds, FIRESTORE_IN_LIMIT)) {
        const studentRefs = studentBatch.map((id) =>
          db.doc(`schools/${schoolId}/students/${id}`)
        );
        const studentSnaps = await db.getAll(...studentRefs);

        for (const snap of studentSnaps) {
          if (!snap.exists) continue;
          const student = snap.data()!;
          const studentName = `${student.firstName ?? ""} ${student.lastName ?? ""}`.trim();
          const parentEmail: string | undefined =
            student.parentEmail ?? student.additionalInfo?.pendingParentEmail;

          if (!parentEmail) {
            recipients.push({
              studentId: snap.id,
              studentName,
              parentEmail: "",
              linkCode: "",
              status: "skipped",
              skippedReason: "no_email",
            });
            continue;
          }

          const enrollmentStatus = student.enrollmentStatus;
          const isSubscribed =
            enrollmentStatus === "book_pack" || enrollmentStatus === "direct_purchase";
          if (!isSubscribed) {
            recipients.push({
              studentId: snap.id,
              studentName,
              parentEmail,
              linkCode: "",
              status: "skipped",
              skippedReason: "not_enrolled",
            });
            continue;
          }

          if (Array.isArray(student.parentIds) && student.parentIds.length > 0) {
            recipients.push({
              studentId: snap.id,
              studentName,
              parentEmail,
              linkCode: "",
              status: "skipped",
              skippedReason: "already_linked",
            });
            continue;
          }

          // Get or create link code
          let linkCode = "";
          if (generateMissingCodes) {
            linkCode = await getOrCreateLinkCode(
              snap.id,
              schoolId,
              createdBy,
              studentName,
            );
          } else {
            const existingCode = await db
              .collection("studentLinkCodes")
              .where("studentId", "==", snap.id)
              .where("status", "==", "active")
              .limit(1)
              .get();
            if (!existingCode.empty) {
              linkCode = existingCode.docs[0].data().code;
            }
          }

          if (!linkCode) {
            recipients.push({
              studentId: snap.id,
              studentName,
              parentEmail,
              linkCode: "",
              status: "skipped",
              skippedReason: "no_active_code",
            });
            continue;
          }

          recipients.push({
            studentId: snap.id,
            studentName,
            parentEmail,
            linkCode,
            status: "sent", // will be updated on failure
          });
        }
      }

      // Group eligible recipients by parent email (multi-child support)
      const emailGroups = new Map<string, OnboardingEmailRecipient[]>();
      for (const r of recipients) {
        if (r.status !== "sent") continue;
        const existing = emailGroups.get(r.parentEmail) ?? [];
        existing.push(r);
        emailGroups.set(r.parentEmail, existing);
      }

      let sentCount = 0;
      let failedCount = 0;
      const skippedCount = recipients.filter((r) => r.status === "skipped").length;

      const senderEmail = sendgridSenderEmail.value() || "noreply@lumi-reading.app";

      // Send emails
      for (const [email, group] of emailGroups) {
        const entries = group.map((r) => ({
          studentName: r.studentName,
          linkCode: r.linkCode,
        }));

        const html = buildOnboardingEmail({
          schoolName,
          entries,
          customMessage,
        });

        try {
          const attachments = await buildOnboardingQrAttachments(entries);
          await sgMail.send({
            to: email,
            from: {email: senderEmail, name: `${schoolName} via Lumi`},
            subject: emailSubject,
            html,
            attachments,
          });
          sentCount++;
        } catch (err) {
          failedCount++;
          const errMsg = err instanceof Error ? err.message : String(err);
          for (const r of group) {
            r.status = "failed";
            r.error = errMsg;
          }
        }
      }

      let finalStatus = "failed";
      if (failedCount === 0 && sentCount > 0) {
        finalStatus = "sent";
      } else if (sentCount > 0 && failedCount > 0) {
        finalStatus = "partial";
      } else if (sentCount === 0 && skippedCount > 0) {
        finalStatus = "sent";
      }

      await docRef.update({
        status: finalStatus,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        recipientCount: recipients.length,
        deliveryCounts: {sent: sentCount, failed: failedCount, skipped: skippedCount},
        recipients: recipients.map((r) => ({
          studentId: r.studentId,
          studentName: r.studentName,
          parentEmail: r.parentEmail,
          linkCode: r.linkCode,
          status: r.status,
          ...(r.error && {error: r.error}),
          ...(r.skippedReason && {skippedReason: r.skippedReason}),
        })),
      });

      functions.logger.info(
        `Onboarding emails for school ${schoolId}: ` +
        `sent=${sentCount}, failed=${failedCount}, skipped=${skippedCount}`
      );
    } catch (error) {
      functions.logger.error("processParentOnboardingEmail error:", error);
      await docRef.update({
        status: "failed",
        errorSummary: error instanceof Error ? error.message : String(error),
      });
    }

    return null;
  });

export const updateClassStats = functions.firestore
  .document("schools/{schoolId}/readingLogs/{logId}")
  .onWrite(async (change, context) => {
    const schoolId = context.params.schoolId;
    const log = change.after.exists ? change.after.data() : null;

    if (!log) return null;

    const studentDoc = await db
      .doc(`schools/${schoolId}/students/${log.studentId}`)
      .get();

    const studentData = studentDoc.data();
    if (!studentData?.classId) return null;

    const classId = studentData.classId;

    // Get student IDs from the class document
    const classDoc = await db.doc(`schools/${schoolId}/classes/${classId}`).get();
    if (!classDoc.exists) return null;

    const classData = classDoc.data() ?? {};
    const classStudentIds: string[] = Array.isArray(classData.studentIds) ?
      classData.studentIds.filter((id: unknown): id is string => typeof id === "string") :
      [];

    if (classStudentIds.length === 0) return null;

    // Aggregate class stats — batch in chunks of 30 (Firestore `in` limit)
    let totalMinutes = 0;
    let totalBooks = 0;
    const uniqueStudents = new Set<string>();

    for (const studentBatch of chunk(classStudentIds, FIRESTORE_IN_LIMIT)) {
      const logsSnapshot = await db
        .collection(`schools/${schoolId}/readingLogs`)
        .where("studentId", "in", studentBatch)
        .where("status", "in", ["completed", "partial"])
        .get();

      logsSnapshot.docs.forEach((doc) => {
        const logData = doc.data();
        totalMinutes += logData.minutesRead || 0;
        totalBooks += logData.bookTitles?.length || 0;
        uniqueStudents.add(logData.studentId);
      });
    }

    await db.doc(`schools/${schoolId}/classes/${classId}`).update({
      "stats.totalMinutesRead": totalMinutes,
      "stats.totalBooksRead": totalBooks,
      "stats.activeStudents": uniqueStudents.size,
      "stats.lastUpdated": admin.firestore.FieldValue.serverTimestamp(),
    });

    return null;
  });

/**
 * Callable: Delete a student with full cascade cleanup.
 * - Removes student from linked parent's linkedChildren array
 * - If a parent has no remaining linked children, deletes their Firestore doc + Auth account
 * - Revokes any active link codes for the student
 * - Deletes the student document
 */
export const deleteStudentWithCascade = functions.https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Must be signed in."
      );
    }

    const {schoolId, studentId} = data as {schoolId: string; studentId: string};
    if (!schoolId || !studentId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "schoolId and studentId are required."
      );
    }

    const studentRef = db.doc(`schools/${schoolId}/students/${studentId}`);
    const studentDoc = await studentRef.get();
    if (!studentDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Student not found.");
    }

    const studentData = studentDoc.data()!;
    const parentIds: string[] = studentData.parentIds ?? [];

    // 1. Clean up each linked parent
    for (const parentId of parentIds) {
      const parentRef = db.doc(`schools/${schoolId}/users/${parentId}`);
      const parentDoc = await parentRef.get();
      if (!parentDoc.exists) continue;

      const linkedChildren: string[] = parentDoc.data()!.linkedChildren ?? [];
      const remaining = linkedChildren.filter((id) => id !== studentId);

      if (remaining.length === 0) {
        // Parent has no other children — delete their account entirely
        await parentRef.delete();
        try {
          await admin.auth().deleteUser(parentId);
        } catch (err) {
          functions.logger.warn(
            `Could not delete Auth user ${parentId} — may not exist`,
            err
          );
        }
      } else {
        await parentRef.update({
          linkedChildren: remaining,
          // Audit trail so a stray "Don't forget to log <name>'s reading"
          // notification can be traced back to the mutation that introduced it.
          linkedChildrenUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          linkedChildrenUpdatedBy: `cascade:deleteStudent:${context.auth.uid}`,
        });
      }
    }

    // 2. Revoke any active link codes for this student
    const codesSnap = await db
      .collection("studentLinkCodes")
      .where("studentId", "==", studentId)
      .where("status", "==", "active")
      .get();

    const batch = db.batch();
    for (const codeDoc of codesSnap.docs) {
      batch.update(codeDoc.ref, {
        status: "revoked",
        revokedAt: admin.firestore.FieldValue.serverTimestamp(),
        revokeReason: "student_deleted",
      });
    }

    // 3. Delete the student document
    batch.delete(studentRef);
    await batch.commit();

    return {success: true, parentsCleaned: parentIds.length};
  }
);

/**
 * Scheduled: Process pending user deletions after the 24-hour cool-off period.
 * Runs hourly. For each user in pendingUserDeletions whose scheduledDeletionAt has passed,
 * permanently deletes the Firebase Auth account and Firestore user document.
 */
export const processPendingUserDeletions = functions.pubsub
  .schedule("0 * * * *") // Every hour on the hour
  .timeZone("UTC")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();

    const snap = await db
      .collection("pendingUserDeletions")
      .where("scheduledDeletionAt", "<=", now)
      .get();

    if (snap.empty) return null;

    let deleted = 0;
    for (const doc of snap.docs) {
      const {userId, schoolId} = doc.data() as {userId: string; schoolId: string};
      try {
        // Delete Firebase Auth account
        try {
          await admin.auth().deleteUser(userId);
        } catch (err) {
          functions.logger.warn(
            `Could not delete Auth user ${userId} — may not exist`,
            err
          );
        }

        // Delete Firestore user document
        await db
          .doc(`schools/${schoolId}/users/${userId}`)
          .delete();

        // Clean up the pending deletion record
        await doc.ref.delete();

        deleted++;
        functions.logger.info(`Permanently deleted user ${userId} from school ${schoolId}`);
      } catch (err) {
        functions.logger.error(`Failed to delete user ${userId}`, err);
      }
    }

    functions.logger.info(`processPendingUserDeletions: deleted ${deleted} users`);
    return null;
  });

// Build the minimal guardian projection denormalized onto student docs.
// Deliberately carries name + relationship label only — never email/phone.
// Uses const-arrow + `//` comments so eslint's valid-jsdoc rule (which only
// fires on `function` declarations with `/** */` blocks) leaves it alone.
const guardianProjection = (
  parentData: admin.firestore.DocumentData
): {name: string; relationshipLabel: string | null} => {
  return {
    name: parentData.fullName ?? "",
    relationshipLabel: parentData.relationshipLabel ?? null,
  };
};

/**
 * Maintains the denormalized `guardianProfiles` map on student docs so a
 * linked guardian can see who else is linked (name + relationship label only)
 * without read access to other parent documents.
 *
 * Triggered on any parent-doc write. Covers account creation, name/label
 * edits, linking, unlinking, and account deletion in one handler. Writes
 * students only — no trigger loop.
 */
export const syncGuardianProfiles = functions.firestore
  .document("schools/{schoolId}/parents/{parentId}")
  .onWrite(async (change, context) => {
    const schoolId = context.params.schoolId;
    const parentId = context.params.parentId;

    const before = change.before.exists ? change.before.data()! : null;
    const after = change.after.exists ? change.after.data()! : null;

    const beforeChildren: string[] = before?.linkedChildren ?? [];
    const afterChildren: string[] = after?.linkedChildren ?? [];

    // Skip writes that can't affect the projection (e.g. fcmToken refresh).
    if (after && before) {
      const sameName = before.fullName === after.fullName;
      const sameLabel = before.relationshipLabel === after.relationshipLabel;
      const sameChildren =
        beforeChildren.length === afterChildren.length &&
        beforeChildren.every((id) => afterChildren.includes(id));
      if (sameName && sameLabel && sameChildren) {
        return null;
      }
    }

    const profileField = new admin.firestore.FieldPath(
      "guardianProfiles",
      parentId
    );

    // Students this parent is no longer linked to (or all, if deleted).
    const removed = beforeChildren.filter((id) => !afterChildren.includes(id));
    // Students currently linked — refresh their projection.
    const current = afterChildren;

    const projection = after ? guardianProjection(after) : null;
    const batch = db.batch();

    for (const studentId of removed) {
      batch.update(
        db.doc(`schools/${schoolId}/students/${studentId}`),
        profileField,
        admin.firestore.FieldValue.delete()
      );
    }
    for (const studentId of current) {
      if (!projection) continue;
      batch.update(
        db.doc(`schools/${schoolId}/students/${studentId}`),
        profileField,
        projection
      );
    }

    try {
      await batch.commit();
    } catch (err) {
      functions.logger.warn(
        `syncGuardianProfiles: partial failure for parent ${parentId}`,
        err
      );
    }
    return null;
  });

/**
 * Companion to syncGuardianProfiles. Fires on student-doc writes; when
 * `parentIds` changes (a guardian linked or unlinked), it (re)writes the
 * guardianProfiles entry for every currently-linked parent — including
 * parents whose own doc was not touched, e.g. the original guardian when a
 * co-parent is added. Loop-safe: writing guardianProfiles does not change
 * parentIds, so the re-trigger sees no change and no-ops.
 */
export const refreshGuardianProfilesOnLink = functions.firestore
  .document("schools/{schoolId}/students/{studentId}")
  .onWrite(async (change, context) => {
    const schoolId = context.params.schoolId;

    const before = change.before.exists ? change.before.data()! : null;
    const after = change.after.exists ? change.after.data()! : null;
    if (!after) return null; // Student deleted — nothing to maintain.

    const beforeParents: string[] = before?.parentIds ?? [];
    const afterParents: string[] = after.parentIds ?? [];

    // React only when the parent set actually changed. This also makes this
    // function's own guardianProfiles write a no-op (parentIds unchanged).
    const sameParents =
      beforeParents.length === afterParents.length &&
      beforeParents.every((id) => afterParents.includes(id));
    if (sameParents) return null;

    const studentRef = change.after.ref;
    const profileField = (parentId: string) =>
      new admin.firestore.FieldPath("guardianProfiles", parentId);
    const batch = db.batch();

    // Drop entries for parents no longer linked.
    for (const parentId of beforeParents.filter(
      (id) => !afterParents.includes(id)
    )) {
      batch.update(
        studentRef,
        profileField(parentId),
        admin.firestore.FieldValue.delete()
      );
    }

    // (Re)write entries for every currently-linked parent.
    for (const parentId of afterParents) {
      const parentSnap = await db
        .doc(`schools/${schoolId}/parents/${parentId}`)
        .get();
      if (!parentSnap.exists) continue;
      batch.update(
        studentRef,
        profileField(parentId),
        guardianProjection(parentSnap.data()!)
      );
    }

    try {
      await batch.commit();
    } catch (err) {
      functions.logger.warn(
        "refreshGuardianProfilesOnLink: failed for student " +
          context.params.studentId,
        err
      );
    }
    return null;
  });

/**
 * Admin-only one-off backfill for `guardianProfiles`. Iterates every parent in
 * the given school and writes their projection onto each linked student. Safe
 * to re-run — writes are idempotent.
 */
export const backfillGuardianProfiles = functions.https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Must be signed in."
      );
    }
    const {schoolId} = data as {schoolId: string};
    if (!schoolId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "schoolId is required."
      );
    }

    const callerDoc = await db
      .doc(`schools/${schoolId}/users/${context.auth.uid}`)
      .get();
    if (!callerDoc.exists || callerDoc.data()!.role !== "schoolAdmin") {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Only a school admin can run the backfill."
      );
    }

    const parentsSnap = await db
      .collection(`schools/${schoolId}/parents`)
      .get();

    let studentsUpdated = 0;
    for (const parentDoc of parentsSnap.docs) {
      const parentData = parentDoc.data();
      const linkedChildren: string[] = parentData.linkedChildren ?? [];
      if (linkedChildren.length === 0) continue;

      const profileField = new admin.firestore.FieldPath(
        "guardianProfiles",
        parentDoc.id
      );
      const projection = guardianProjection(parentData);

      const batch = db.batch();
      for (const studentId of linkedChildren) {
        batch.update(
          db.doc(`schools/${schoolId}/students/${studentId}`),
          profileField,
          projection
        );
        studentsUpdated++;
      }
      try {
        await batch.commit();
      } catch (err) {
        functions.logger.warn(
          `backfillGuardianProfiles: failed for parent ${parentDoc.id}`,
          err
        );
      }
    }

    return {success: true, parentsProcessed: parentsSnap.size, studentsUpdated};
  }
);

/**
 * On Comment Created
 *
 * Fires when a message is posted to a reading log's comment thread at
 * `schools/{schoolId}/readingLogs/{logId}/comments/{commentId}`.
 *
 * Teacher → parent: mirrors the latest teacher message onto the log's legacy
 * `teacherComment`/`commentedAt`/`commentedBy` fields (so the existing
 * parent-side display keeps working) and pushes the parent an FCM notification,
 * respecting their push preference and the school's quiet hours.
 *
 * Parent → teacher: no push. Teachers have no FCM tokens registered, so a
 * parent reply surfaces as an in-app unread badge instead (handled client-side
 * via the log's denormalized `lastComment*` fields).
 */
export const onCommentCreated = functions.firestore
  .document("schools/{schoolId}/readingLogs/{logId}/comments/{commentId}")
  .onCreate(async (snap, context) => {
    const {schoolId, logId} = context.params as {
      schoolId: string;
      logId: string;
    };
    const comment = snap.data() ?? {};

    // Only teacher comments drive a push; parent replies show as an in-app
    // badge (no staff tokens exist yet).
    if (comment.authorRole !== "teacher") return null;

    const logRef = snap.ref.parent.parent;
    if (!logRef) return null;

    const body = typeof comment.body === "string" ? comment.body : "";
    const authorName =
      typeof comment.authorName === "string" ? comment.authorName : "Teacher";

    // Mirror the latest teacher message onto the log for the legacy
    // single-comment display surfaces.
    await logRef.update({
      teacherComment: body,
      commentedAt:
        comment.createdAt ?? admin.firestore.FieldValue.serverTimestamp(),
      commentedBy: authorName,
    });

    const parentId =
      typeof comment.parentId === "string" ? comment.parentId : "";
    if (!parentId) return null;

    // Teacher-proxy logs store the teacher's own UID in `parentId`. If the
    // recipient is the comment author, there's no real parent to notify.
    if (parentId === comment.authorId) return null;

    const parentSnap = await db
      .doc(`schools/${schoolId}/parents/${parentId}`)
      .get();
    if (!parentSnap.exists) return null;
    const parentData = parentSnap.data() ?? {};
    if (parentData.isActive === false) return null;

    const pushEnabled =
      parentData.preferences?.pushNotificationsEnabled !== false;
    const token =
      typeof parentData.fcmToken === "string" ? parentData.fcmToken : undefined;
    if (!pushEnabled || !token) return null;

    // Respect the school's quiet hours (the thread + badge still land; only the
    // push is suppressed).
    const schoolSnap = await db.doc(`schools/${schoolId}`).get();
    const schoolData = schoolSnap.data() ?? {};
    const timezone = String(schoolData.timezone ?? "UTC");
    if (isWithinQuietHours(new Date(), timezone, schoolData.quietHours)) {
      functions.logger.info("Comment push suppressed by quiet hours", {
        schoolId,
        logId,
      });
      return null;
    }

    const studentId = String(comment.studentId ?? "");
    const preview = body.length > 120 ? `${body.slice(0, 117)}...` : body;

    try {
      await admin.messaging().send({
        token,
        notification: {
          title: `New comment from ${authorName}`,
          body: preview,
        },
        data: {
          type: "comment_reply",
          logId,
          schoolId,
          studentId,
        },
        apns: {payload: {aps: {sound: "default"}}},
        android: {
          priority: "high" as const,
          notification: {
            sound: "default",
            clickAction: "FLUTTER_NOTIFICATION_CLICK",
          },
        },
      });
      functions.logger.info("Comment notification sent", {
        schoolId,
        logId,
        parentId,
      });
    } catch (error) {
      functions.logger.error("Failed to send comment notification", {
        schoolId,
        logId,
        parentId,
        error: error instanceof Error ? error.message : String(error),
      });
    }

    return null;
  });
