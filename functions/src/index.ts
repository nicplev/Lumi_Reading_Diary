// MUST be first: sets v2 global options (region + pinned SA) before any
// function in any file is defined. See functions/src/global_options.ts.
import "./global_options";
import * as functions from "firebase-functions/v1";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onDocumentWritten, onDocumentCreated, onDocumentUpdated} from "firebase-functions/v2/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as admin from "firebase-admin";
import * as crypto from "crypto";
import sgMail from "@sendgrid/mail";

const sendgridApiKey = defineSecret("SENDGRID_API_KEY_AU");
const sendgridSenderEmail = defineSecret("SENDGRID_SENDER_EMAIL_AU");
import {
  isDueAt,
  isWithinQuietHours,
  excludeAmbiguousPushTokenRecipients,
  mergePushTargetsByToken,
  mergeRecipientsByParent,
  NotificationAudienceType,
  normalizeNotificationPermissions,
  parseReminderHour,
  validateNotificationAudience,
} from "./notification_helpers";
import {buildOnboardingEmail, buildOnboardingQrAttachments, buildStaffOnboardingEmail} from "./email_templates";
import {assertNotReadOnly} from "./read_only_guard";
import {recordCronRun} from "./ops_heartbeat";
import {lumiMascotAttachment} from "./email_assets";
import {generateTempPassword} from "./temp_password";
import {
  DEFAULT_ACHIEVEMENT_THRESHOLDS,
  computeAwardableAchievements,
  type AchievementThresholdSet,
} from "./achievements";
import {
  MAX_REST_DAYS,
  buildIsCountingDay,
  computeGentleStreak,
  computeLongestStreak,
  countInWindow,
  localDateString,
  parseTermDates,
  shiftDays,
} from "./dateUtils";
import {DEFAULT_TIMEZONE} from "./access";
import {errorCodeForLog} from "./log_safety";
import {
  applyClassStatsDelta,
  applyStudentStatsDelta,
  classAggregationStudentBatches,
  isInvalidatedLog,
  isStatsNoopUpdate,
  readIncrementalConfig,
  runReconcilePass,
} from "./stats_aggregation";
import {runStreakRefreshPass} from "./streak_refresh";
import {runStateTermDatesFillPass} from "./term_dates_fallback";
import {
  reconcileClassDailyReadingPass,
  syncReadingLogDailySummary,
} from "./class_daily_reading";

// App Check enforcement, opt-in via env var (default OFF). Matches
// code_verification.ts / impersonation.ts — flip a flag only AFTER the client
// attestation rollout is verified in the App Check console, else a
// half-rolled-out App Check locks out real clients (1.6). App Check attests the
// APP, not the account, so it's safe on unauthenticated/pre-account calls too.
const NOTIFICATION_CAMPAIGN_APP_CHECK_ENFORCED =
  process.env.NOTIFICATION_CAMPAIGN_APP_CHECK_ENFORCED === "true";

// Library counts denormalization. Maintains schools/{id}/libraryMeta/counts
// so the paginated library screen can render header badges without reading
// the full books collection. See functions/src/library_counts.ts.
export {maintainLibraryCounts} from "./library_counts";

// Server-owned, sharded class/day summaries used by teacher dashboards.
// The synchronizer reads the current source log inside an idempotent
// transaction, so duplicate and out-of-order Firestore events converge.
export const maintainClassDailyReading = onDocumentWritten(
  {
    document: "schools/{schoolId}/readingLogs/{logId}",
    // The synchronizer is idempotent, so retrying transient failures is safe
    // and avoids waiting for the weekly reconciliation to heal missed events.
    retry: true,
  },
  async (event) => {
    await syncReadingLogDailySummary(event.params.schoolId, event.params.logId);
  },
);

export const reconcileClassDailyReadingScheduled = onSchedule(
  {
    schedule: "every sunday 04:30",
    timeZone: "Australia/Melbourne",
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async () => {
    try {
      const result = await reconcileClassDailyReadingPass();
      functions.logger.info("class daily reading reconciliation complete", result);
      await recordCronRun(
        "reconcileClassDailyReadingScheduled",
        "ok",
        `${result.schools} schools; ${result.logs} logs; ` +
          `${result.summaries} summaries`,
      );
    } catch (err) {
      const errorCode = errorCodeForLog(err);
      functions.logger.error("class daily reading reconciliation failed", {
        errorCode,
      });
      await recordCronRun(
        "reconcileClassDailyReadingScheduled",
        "error",
        errorCode,
      );
      throw err;
    }
  },
);

// Live bucket-usage counters (opsMetrics/storageUsage) for the super-admin
// dashboard: storage triggers keep the totals current, a nightly reconcile
// heals drift. See functions/src/storage_usage.ts.
export {
  trackStorageObjectFinalized,
  trackStorageObjectDeleted,
  reconcileStorageUsage,
} from "./storage_usage";

// Per-phone-number SMS rate-limit gate. Clients call this before
// invoking verifyPhoneNumber to enforce a daily cap. See
// functions/src/sms_rate_limit.ts for the policy and rollout notes.
export {requestSmsVerification} from "./sms_rate_limit";

// Server-side phone second-factor enrollment. Identity Platform blocks
// client-side MFA enrollment on unverified emails; the client links the
// SMS-verified phone and this enrolls it via the Admin SDK. See
// functions/src/mfa_enrollment.ts.
export {
  enrollLinkedPhoneAsMfa,
  finalizeEmailSignup,
  syncUserMfaProfileState,
} from "./mfa_enrollment";

// Phone-primary parent signup finalisation (no MFA enroll). Writes the parent
// doc + indexes + child link server-side so the client self-create can be
// denied by the rules (1.3). See functions/src/mfa_enrollment.ts.
export {finalizeParentSignup} from "./mfa_enrollment";

admin.initializeApp();
const db = admin.firestore();

// ─────────────────────────────────────────────────────────────────────────────
// Developer impersonation pipeline (read-only, fully-audited). See
// functions/src/impersonation.ts for the implementation. Re-exported so the
// Firebase CLI picks them up as deployable functions.
// ─────────────────────────────────────────────────────────────────────────────
export {
  checkDevAccess,
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
  verifyStudentLinkCode,
  createCoParentInvite,
} from "./parent_linking";

// Server-side, exact-code verification for parent link codes and school join
// codes. Replaces the client-side collection queries that required the
// unauthenticated `list` rules (enumeration risk). See code_verification.ts.
export {verifySchoolCode} from "./code_verification";

// Login-fallback school resolution (finding #5 enabler). Lets the app resolve an
// un-indexed user's school server-side instead of listing the whole /schools
// collection client-side, so the cross-tenant `allow list` rule on /schools can
// later be removed. Dormant until the app adopts it. See school_resolution.ts.
export {resolveUserSchoolByUid} from "./school_resolution";

// Server-owned O(1) UID-to-membership index. These triggers remove the last
// login fallback that scanned every school's membership subcollection.
export {
  maintainParentMembershipIndex,
  maintainStaffMembershipIndex,
} from "./membership_index";

// Access/licensing lifecycle. T1 reacts to subscription changes to recompute
// school.access + cascade student access. T2 (renewStudents callable) + T4
// (annualRollover cron) live in functions/src/renewals.ts. See
// functions/src/access.ts for the shared AU boundary math.
export {onSchoolSubscriptionWrite} from "./subscriptions";
export {grantAccessOnStudentCreate} from "./whole_school_access";
export {processInvoiceEmail} from "./invoice_email";
export {renewStudents, annualRollover} from "./renewals";
export {topReaderAward} from "./top_reader_award";
export {submitDemoRequest, submitContactSalesInquiry} from "./marketing_leads";

// Daily cleanup for comprehension audio + per-row teacher/school-admin
// trash button. The cron is driven by /platformConfig/comprehensionRetention
// written from the super-admin portal. deleteComprehensionAudio is the only
// path through which a non-system principal can delete an audio object —
// storage.rules denies all client deletes. See
// functions/src/comprehension_retention.ts.
export {
  cleanupComprehensionAudio,
  cleanupPendingComprehensionAudio,
  confirmComprehensionAudioUpload,
  deleteComprehensionAudio,
  getComprehensionAudioUrl,
  validateComprehensionAudioMedia,
} from "./comprehension_retention";

// Idempotent account/student deletion jobs. All destructive work runs through
// server-owned callables/the retry scheduler; clients can only request and
// read their own sanitized job status.
export {
  getMyDeletionStatus,
  processPendingUserDeletions,
  requestAccountDeletion,
  requestStudentDeletion,
} from "./deletion";

// Demo-day rolling access. processDemoAccessEmail emails a prospect the day's
// demo credentials (freshness-gated); scrambleDemoPasswords nightly-rotates
// every demo account so a demo-day password only works its own Sydney day.
// The portal issues the day password into demoAccess/state via server-ops. See
// functions/src/demo_access.ts and docs/DEMO_DAY_ACCESS_PLAN.md.
export {processDemoAccessEmail, scrambleDemoPasswords} from "./demo_access";

/**
 * CRITICAL SECURITY: Stats Aggregation
 * Prevents client-side manipulation of student statistics
 * Triggered on every reading log create, update, AND delete — the delete
 * path powers the widget-undo banner in the parent app, which deletes the
 * log doc and relies on this trigger to recompute the student's stats from
 * the remaining logs.
 */
export const aggregateStudentStats = onDocumentWritten(
  {document: "schools/{schoolId}/readingLogs/{logId}", concurrency: 1},
  async (event) => {
    if (!event.data) return;
    // Metadata-only updates (validation stamps, teacher-comment mirrors)
    // can't change any stat — skip before spending a single read.
    if (isStatsNoopUpdate(event.data)) return;
    const schoolId = event.params.schoolId;

    // On delete, pull identity from the pre-delete snapshot. Resolve this
    // before selecting the incremental/legacy path so both implementations
    // honour the student-deletion guard below.
    const log = event.data.after.exists ?
      event.data.after.data() :
      event.data.before.data();
    if (!log) {
      functions.logger.warn("Reading log write event with no before or after data");
      return;
    }
    const studentId = log.studentId;
    if (!studentId) {
      functions.logger.warn("Reading log has no studentId");
      return;
    }
    const studentRef = db.doc(`schools/${schoolId}/students/${studentId}`);
    const deletionGuard = await studentRef.get();
    if (!deletionGuard.exists || deletionGuard.data()?.pendingDeletion === true) {
      return;
    }

    // When the incremental flag is on, dispatch to the O(1)-reads path.
    // The new path self-heals (falls back to full recompute) if a student's
    // readingDates array hasn't been seeded yet by the backfill script.
    const incremental = await readIncrementalConfig();
    if (incremental.studentStats) {
      try {
        await applyStudentStatsDelta(event.data, schoolId);
      } catch (err) {
        functions.logger.error("applyStudentStatsDelta failed", {
          errorCode: errorCodeForLog(err),
        });
        throw err;
      }
      return;
    }

    // Legacy path: full re-aggregation. Retained as the authoritative
    // implementation behind the flag until the incremental path has been
    // observed clean for at least one reconciler cycle.
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
      const schoolData = schoolSnap.data() ?? {};
      const tz = schoolData.timezone ?? DEFAULT_TIMEZONE;
      const isCountingDay =
        buildIsCountingDay(parseTermDates(schoolData.termDates));

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
        if (isInvalidatedLog(logData)) return;
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
      // own, and school-holiday days (outside termDates) never count against
      // it — see computeGentleStreak in ./dateUtils.
      const {currentStreak, restDaysRemaining} =
        computeGentleStreak(readingDates, today, MAX_REST_DAYS, isCountingDay);

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
        totalMinutesRead,
        totalBooksRead,
        currentStreak,
      });

      return;
    } catch (error) {
      functions.logger.error("Error aggregating student stats", {
        errorCode: errorCodeForLog(error),
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
    const storedToken = typeof parentData.fcmToken === "string" ?
      parentData.fcmToken.trim() :
      "";

    deliveries.push({
      parentId: recipient.parentId,
      parentRef: parentDoc.ref,
      token: pushEnabled && storedToken.length > 0 ? storedToken : undefined,
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

// Recipient budgets — a school-wide campaign fans out parent-doc reads,
// two inbox writes, and a push per parent, so an unbounded audience is a
// direct bill risk (the only existing limit was 10 campaigns/sender/hour,
// which still allows 10 × whole-school fan-outs). Both caps are overridable
// via platformConfig/notificationLimits ({maxRecipientsPerCampaign,
// maxRecipientsPerSchoolPerDay}); a missing doc/field falls back to these.
const DEFAULT_MAX_RECIPIENTS_PER_CAMPAIGN = 2500;
const DEFAULT_MAX_RECIPIENTS_PER_SCHOOL_PER_DAY = 5000;

async function readNotificationLimits(): Promise<{
  maxRecipientsPerCampaign: number;
  maxRecipientsPerSchoolPerDay: number;
}> {
  const snap = await db.doc("platformConfig/notificationLimits").get();
  const data = snap.data() ?? {};
  const num = (value: unknown, fallback: number) =>
    typeof value === "number" && Number.isFinite(value) && value > 0 ?
      value :
      fallback;
  return {
    maxRecipientsPerCampaign:
      num(data.maxRecipientsPerCampaign, DEFAULT_MAX_RECIPIENTS_PER_CAMPAIGN),
    maxRecipientsPerSchoolPerDay: num(
      data.maxRecipientsPerSchoolPerDay,
      DEFAULT_MAX_RECIPIENTS_PER_SCHOOL_PER_DAY,
    ),
  };
}

/**
 * Atomically reserves `count` recipients from the school's daily budget.
 * The window is a UTC calendar day — coarse by design: this is a runaway
 * guard, not an accounting system.
 * @param {string} schoolId School whose budget to draw from.
 * @param {number} count Recipients this campaign wants to send to.
 * @param {number} cap Daily per-school recipient cap.
 * @return {Promise<boolean>} False when the reservation would exceed the cap.
 */
async function reserveDailyRecipientBudget(
  schoolId: string,
  count: number,
  cap: number,
): Promise<boolean> {
  const budgetRef =
    schoolRef(schoolId).collection("meta").doc("notificationBudget");
  const today = new Date().toISOString().slice(0, 10);
  return db.runTransaction(async (transaction) => {
    const snap = await transaction.get(budgetRef);
    const data = snap.data() ?? {};
    const used = data.date === today ? Number(data.recipients ?? 0) : 0;
    if (used + count > cap) return false;
    transaction.set(budgetRef, {
      date: today,
      recipients: used + count,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  });
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

    // Recipient budgets: reject over-cap audiences BEFORE any inbox writes
    // or pushes go out, using the same clean "failed" shape as the
    // empty-audience case above.
    const limits = await readNotificationLimits();
    const failCounts = {
      recipientCounts: {parents: deliveries.length, students: students.length},
      deliveryCounts: {inboxWritten: 0, pushSent: 0, pushFailed: 0},
    };
    if (deliveries.length > limits.maxRecipientsPerCampaign) {
      await campaignRef.update({
        status: "failed",
        errorSummary:
          `Audience of ${deliveries.length} parents exceeds the ` +
          `per-campaign limit of ${limits.maxRecipientsPerCampaign}. ` +
          "Narrow the audience (e.g. send per class) and try again.",
        ...failCounts,
      });
      return;
    }
    const reserved = await reserveDailyRecipientBudget(
      schoolId, deliveries.length, limits.maxRecipientsPerSchoolPerDay,
    );
    if (!reserved) {
      await campaignRef.update({
        status: "failed",
        errorSummary:
          "Your school has reached its daily notification limit " +
          `(${limits.maxRecipientsPerSchoolPerDay} recipients). ` +
          "Try again tomorrow.",
        ...failCounts,
      });
      return;
    }

    await createParentInboxItems(deliveries, campaignRef.id, campaign);

    const statusByParentId = new Map<string, string>();
    const tokenMessages: admin.messaging.TokenMessage[] = [];
    const tokenOwnerGroups: string[][] = [];
    const inboxWritten = deliveries.length;

    for (const delivery of deliveries) {
      if (!delivery.token) {
        statusByParentId.set(delivery.parentId, "skipped_no_token");
        continue;
      }
    }

    // A device token can remain on more than one parent document after account
    // switching on a shared device. Send once per unique token, while retaining
    // every parent owner so all inbox status documents stay correct.
    const pushTargets = mergePushTargetsByToken(deliveries);
    const tokenOwnerCount = deliveries.filter((delivery) => delivery.token).length;
    if (pushTargets.length < tokenOwnerCount) {
      functions.logger.info("Deduplicated notification campaign device tokens", {
        tokenOwners: tokenOwnerCount,
        uniquePushTargets: pushTargets.length,
      });
    }
    for (const target of pushTargets) {
      tokenOwnerGroups.push(target.parentIds);
      tokenMessages.push({
        token: target.token,
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
        // Collapse-id is defense in depth for provider retries: one campaign
        // should occupy one notification slot on each Apple device.
        apns: {
          headers: {"apns-collapse-id": campaignRef.id},
          payload: {aps: {sound: "default"}},
        },
        android: {
          collapseKey: campaignRef.id,
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
      const ownerBatch = tokenOwnerGroups.slice(i, i + FCM_BATCH_LIMIT);
      const result = await admin.messaging().sendEach(messageBatch);

      pushSent += result.successCount;
      pushFailed += result.failureCount;

      result.responses.forEach((response, index) => {
        const parentIds = ownerBatch[index] ?? [];
        if (response.success) {
          parentIds.forEach((parentId) => statusByParentId.set(parentId, "sent"));
          return;
        }

        parentIds.forEach((parentId) => statusByParentId.set(parentId, "failed"));
        const code = response.error?.code;
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token"
        ) {
          parentIds.forEach((parentId) => staleParentIds.add(parentId));
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

export const createNotificationCampaign = onCall(
  {
    timeoutSeconds: 60,
    memory: "256MiB",
    enforceAppCheck: NOTIFICATION_CAMPAIGN_APP_CHECK_ENFORCED,
    consumeAppCheckToken: NOTIFICATION_CAMPAIGN_APP_CHECK_ENFORCED,
  },
  async (request) => {
    const rawData: NotificationCampaignPayload = request.data;
    assertNotReadOnly(request);
    const senderId = request.auth?.uid;
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

export const processQueuedNotificationCampaign = onDocumentCreated(
  {document: "schools/{schoolId}/notificationCampaigns/{campaignId}", concurrency: 1},
  async (event) => {
    if (!event.data) return;
    const campaign = event.data.data() as NotificationCampaignData;
    if (campaign.status !== "queued") {
      return;
    }

    await dispatchNotificationCampaign(event.params.schoolId, event.data.ref);
    return;
  });

export const dispatchScheduledNotificationCampaigns = onSchedule(
  {
    // Worst-case scheduling latency: a campaign with scheduledFor=10:01 fires
    // at 10:05 instead of 10:01. Acceptable for non-urgent broadcasts and
    // cuts invocations + collectionGroup scans by 80%.
    schedule: "every 5 minutes",
    timeZone: "UTC",
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async () => {
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

    await recordCronRun("dispatchScheduledNotificationCampaigns", "ok");
    return;
  });

/**
 * Process reminders for a single school.
 *
 * Flow:
 *  1. Determine local hour/weekday from school timezone.
 *  2. Fetch parents with tokens — filter eligible in memory.
 *  3. Gather student IDs from eligible parents' linkedChildren (no full students read).
 *  4. Check which of those students logged today (batched `in` queries).
 *  5. Build ONE message per unambiguous parent device listing un-logged children.
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
  const schoolTz = schoolData.timezone || DEFAULT_TIMEZONE;
  const {hour: localHour, weekday: localWeekday} = getLocalTime(utcNow, schoolTz);

  // Quiet hours check
  if (isWithinQuietHours(utcNow, schoolTz, schoolData.quietHours)) {
    return {sent: 0, failed: 0, stale: 0};
  }

  // ---- Step 1: Fetch parents due THIS hour ----
  // Equality on the denormalized `reminderHour` (maintained by the
  // syncParentReminderHour mirror trigger, seeded for existing docs by
  // scripts/backfill_reminder_hour.js) reads ~1/24th of parents per hourly
  // tick instead of every tokened parent every hour. Parents missing the
  // field are invisible to this query — run the backfill right after
  // deploying this change.
  const parentsSnap = await db
    .collection(`schools/${schoolId}/parents`)
    .where("reminderHour", "==", localHour)
    .get();

  if (parentsSnap.empty) return {sent: 0, failed: 0, stale: 0};

  // ---- Step 2: Filter eligible parents in memory ----
  interface EligibleParent {
    parentId: string;
    token: string;
    linkedChildren: string[]; // student IDs
  }

  const eligible: EligibleParent[] = [];

  for (const pDoc of parentsSnap.docs) {
    const p = pDoc.data();
    if (!p.fcmToken) continue;
    if (p.preferences?.notificationsEnabled === false) continue;

    // Hour check (default 19 / 7 PM — matches the app's default time).
    // Defense-in-depth re-derivation from preferences: a stale denormalized
    // reminderHour (e.g. a direct doc edit while the mirror trigger was
    // down) must not cause a wrong-hour send.
    if (parseReminderHour(p.preferences?.reminderTime) !== localHour) continue;

    // Day-of-week check. Unset → default Mon–Thu (the app's school-night
    // default). A legacy empty list meant "every day", so honour that; any
    // explicit list is used as-is.
    const rawDays = p.preferences?.reminderDays;
    let days: number[];
    if (!Array.isArray(rawDays)) {
      days = [1, 2, 3, 4];
    } else if (rawDays.length === 0) {
      days = [1, 2, 3, 4, 5, 6, 7];
    } else {
      days = rawDays as number[];
    }
    if (!days.includes(localWeekday)) continue;

    const children: string[] = p.linkedChildren ?? [];
    if (children.length === 0) continue;

    eligible.push({parentId: pDoc.id, token: p.fcmToken, linkedChildren: children});
  }

  if (eligible.length === 0) return {sent: 0, failed: 0, stale: 0};

  // A reading reminder contains child names, unlike a generic school campaign.
  // Never choose an arbitrary record when a token is attached to multiple due
  // parent accounts: suppress it until the ownership trigger resolves it.
  const {
    recipients: unambiguousParents,
    suppressedTokens,
  } = excludeAmbiguousPushTokenRecipients(eligible);
  if (suppressedTokens.length > 0) {
    functions.logger.warn("Suppressed ambiguous reading reminder device targets", {
      tokenCount: suppressedTokens.length,
    });
  }
  if (unambiguousParents.length === 0) return {sent: 0, failed: 0, stale: 0};

  // Do not read a child's activity or name when their reminder is suppressed.
  const allStudentIds = new Set<string>();
  unambiguousParents.forEach((parent) => {
    parent.linkedChildren.forEach((childId) => allStudentIds.add(childId));
  });

  // ---- Step 3: Check which students logged today ----
  // Use batched `in` queries on readingLogs (max 30 per query).
  // "Today" is the SCHOOL-LOCAL calendar day, not UTC: query a generous UTC
  // window (±1 day) and decide membership in memory by the local date string
  // (same pattern as topReaderAward) — a 23:30 local log must count as
  // tonight, not tomorrow, or the family gets a redundant reminder.
  const todayStr = localDateString(utcNow, schoolTz);
  const windowStartTs = admin.firestore.Timestamp.fromDate(
    new Date(`${shiftDays(todayStr, -1)}T00:00:00Z`),
  );
  const windowEndTs = admin.firestore.Timestamp.fromDate(
    new Date(`${shiftDays(todayStr, 2)}T00:00:00Z`),
  );

  const loggedToday = new Set<string>();
  const studentIdBatches = chunk([...allStudentIds], FIRESTORE_IN_LIMIT);

  await Promise.all(studentIdBatches.map(async (batch) => {
    const snap = await db
      .collection(`schools/${schoolId}/readingLogs`)
      .where("studentId", "in", batch)
      .where("date", ">=", windowStartTs)
      .where("date", "<", windowEndTs)
      .select("studentId", "date")
      .get();
    snap.docs.forEach((d) => {
      const ts = d.data().date as admin.firestore.Timestamp | undefined;
      const dt = ts?.toDate?.();
      if (!dt || localDateString(dt, schoolTz) !== todayStr) return;
      loggedToday.add(d.data().studentId as string);
    });
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
        const student = d.data() ?? {};
        const access = student.access ?? {};
        const rawExpiry = access.expiresAt;
        const expiresAtMs = rawExpiry instanceof admin.firestore.Timestamp ?
          rawExpiry.toMillis() :
          rawExpiry instanceof Date ? rawExpiry.getTime() : 0;
        if (
          student.isActive !== false &&
          access.status === "active" &&
          expiresAtMs > utcNow.getTime()
        ) {
          studentNames.set(d.id, student.firstName ?? "your child");
        }
      }
    });
  }));

  // ---- Step 5: Build ONE message per parent ----
  const messages: admin.messaging.TokenMessage[] = [];
  const msgParentIds: string[] = [];

  for (const parent of unambiguousParents) {
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
    msgParentIds.push(parent.parentId);
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
 * Mirrors `preferences.reminderTime` into a top-level `reminderHour` field
 * on parent docs so sendReadingReminders can query only the parents due at
 * the current hour instead of reading every tokened parent every hour
 * (~24× fewer parent reads per day).
 *
 * Self-terminating: the mirror write re-fires this trigger once, finds the
 * value already correct, and returns without writing. Zero reads — all data
 * comes from the event snapshot. scripts/backfill_reminder_hour.js stamps
 * existing docs; this keeps them in sync from then on (including doc
 * creation, so new parents never need the backfill).
 */
export const syncParentReminderHour = onDocumentWritten(
  {document: "schools/{schoolId}/parents/{parentId}", concurrency: 10},
  async (event) => {
    if (!event.data?.after.exists) return;
    const data = event.data.after.data() ?? {};
    const desired = parseReminderHour(data.preferences?.reminderTime);
    if (data.reminderHour === desired) return;
    await event.data.after.ref.update({reminderHour: desired});
  });

/**
 * An FCM token identifies an app installation, not a Lumi account. Make the
 * most recently authenticated parent its sole owner, so a shared or
 * account-switched device cannot receive another family's child-specific push.
 * This server-side guard also protects older app versions that write the token
 * directly to Firestore.
 */
export const enforceUniqueParentFcmToken = onDocumentWritten(
  {document: "schools/{schoolId}/parents/{parentId}", concurrency: 10},
  async (event) => {
    if (!event.data?.after.exists) return;
    const parentRef = event.data.after.ref;

    const after = event.data.after.data() ?? {};
    const token = typeof after.fcmToken === "string" ? after.fcmToken.trim() : "";
    if (!token) return;

    const before = event.data.before.exists ? event.data.before.data() ?? {} : {};
    const previousToken = typeof before.fcmToken === "string" ? before.fcmToken.trim() : "";
    const beforeUpdatedAt = before.fcmTokenUpdatedAt?.toMillis?.() ?? null;
    const afterUpdatedAt = after.fcmTokenUpdatedAt?.toMillis?.() ?? null;

    // A profile/preference write must not unexpectedly reclaim a token. Token
    // registration updates fcmTokenUpdatedAt, while a new token differs from
    // the prior value.
    if (previousToken === token && beforeUpdatedAt === afterUpdatedAt) return;

    const removedOwners = await db.runTransaction(async (transaction) => {
      // Re-read within the transaction so out-of-order trigger delivery can
      // never let an earlier sign-in evict a later sign-in from the same phone.
      const claimant = await transaction.get(parentRef);
      const claimedToken = typeof claimant.data()?.fcmToken === "string" ?
        claimant.data()?.fcmToken.trim() : "";
      if (!claimant.exists || claimedToken !== token) return 0;

      const owners = await transaction.get(
        db.collectionGroup("parents").where("fcmToken", "==", token),
      );
      if (owners.size < 2) return 0;

      const newestOwner = owners.docs.reduce((newest, candidate) => {
        const newestUpdatedAt = newest.data().fcmTokenUpdatedAt?.toMillis?.() ?? 0;
        const candidateUpdatedAt = candidate.data().fcmTokenUpdatedAt?.toMillis?.() ?? 0;
        if (candidateUpdatedAt !== newestUpdatedAt) {
          return candidateUpdatedAt > newestUpdatedAt ? candidate : newest;
        }
        return candidate.ref.path > newest.ref.path ? candidate : newest;
      });
      if (newestOwner.ref.path !== claimant.ref.path) return 0;

      const staleOwners = owners.docs.filter((doc) => doc.ref.path !== claimant.ref.path);
      // Firestore transactions allow at most 500 writes. Requiring an
      // implausibly large duplicate set to be remediated manually is safer
      // than partially changing ownership.
      if (staleOwners.length > 499) {
        functions.logger.error("Too many duplicate FCM token owners to clear atomically", {
          tokenOwnerCount: owners.size,
        });
        return 0;
      }

      for (const owner of staleOwners) {
        transaction.update(owner.ref, {
          fcmToken: admin.firestore.FieldValue.delete(),
          fcmTokenUpdatedAt: admin.firestore.FieldValue.delete(),
        });
      }
      return staleOwners.length;
    });
    if (removedOwners === 0) return;

    functions.logger.warn("Removed duplicate parent FCM token ownership", {
      removedOwners,
    });
  });

/**
 * Send reading reminder notifications to parents.
 *
 * Runs every hour. Uses school timezone to match each parent's preferred
 * reminder hour and day-of-week. One notification per parent (not per child).
 * Processes schools with bounded concurrency and sends FCM in 500-msg chunks.
 *
 * Firestore reads per school ≈ parents(due this hour) + unlogged_students +
 * log_checks (NOT all students × all logs like the naive approach)
 */
export const sendReadingReminders = onSchedule(
  {
    schedule: "0 * * * *", // Every hour on the hour
    timeZone: "UTC",
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async () => {
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

      await recordCronRun("sendReadingReminders", "ok");
      return;
    } catch (error) {
      functions.logger.error("Error in sendReadingReminders", {
        errorCode: errorCodeForLog(error),
      });
      await recordCronRun("sendReadingReminders", "error",
        errorCodeForLog(error));
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
export const pruneStaleFcmTokens = onSchedule(
  {
    schedule: "0 4 * * 1",
    timeZone: "UTC",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
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
      await recordCronRun("pruneStaleFcmTokens", "ok");
    } catch (error) {
      functions.logger.error("Error in pruneStaleFcmTokens", {
        errorCode: errorCodeForLog(error),
      });
      await recordCronRun("pruneStaleFcmTokens", "error",
        errorCodeForLog(error));
      throw error;
    }
  });


// ─── Achievement evaluation: pure logic + constants live in
// ./achievements.ts (testable). Only the Firestore-backed threshold
// loader stays here.

/**
 * Resolves the achievement thresholds for a school.
 *
 * Per-school achievement customisation is DISABLED for first release: every
 * school uses the platform defaults, regardless of any `settings.
 * achievementThresholds` left on the school doc. (To re-enable later, read
 * `schoolDoc.data()?.settings?.achievementThresholds` here again.)
 * @param {string} schoolId School id (unused while customisation is disabled).
 * @return {Promise<AchievementThresholdSet>} The platform default thresholds.
 */
async function resolveAchievementThresholds(
  schoolId: string,
): Promise<AchievementThresholdSet> {
  void schoolId;
  return {
    streak: DEFAULT_ACHIEVEMENT_THRESHOLDS.streak,
    books: DEFAULT_ACHIEVEMENT_THRESHOLDS.books,
    minutes: DEFAULT_ACHIEVEMENT_THRESHOLDS.minutes,
    readingDays: DEFAULT_ACHIEVEMENT_THRESHOLDS.readingDays,
  };
}


/**
 * Achievement Detector
 * Triggers when student stats are updated to check for new achievements.
 * Reads school-level custom thresholds (falls back to defaults if not set).
 * Awards all 14 tier achievements + the first_log special achievement, on
 * current state (idempotent — never double-awards thanks to arrayUnion).
 */
export const detectAchievements = onDocumentUpdated(
  {document: "schools/{schoolId}/students/{studentId}", concurrency: 1},
  async (event) => {
    if (!event.data) return;
    const schoolId = event.params.schoolId;
    const studentId = event.params.studentId;
    const newData = event.data.after.data();
    const newStats = newData.stats || {};

    // This fires on EVERY student-doc update (character picks, award writes,
    // its own arrayUnion, stats no-op rewrites). Achievements are driven
    // solely by totalMinutesRead + totalReadingDays (see
    // computeAwardableAchievements) — if neither moved, skip before paying
    // the threshold-config read.
    const oldStats = event.data.before.data()?.stats || {};
    if (
      Number(oldStats.totalMinutesRead ?? 0) ===
        Number(newStats.totalMinutesRead ?? 0) &&
      Number(oldStats.totalReadingDays ?? 0) ===
        Number(newStats.totalReadingDays ?? 0)
    ) {
      return;
    }

    const thresholds = await resolveAchievementThresholds(schoolId);

    // Build set of already-earned IDs to prevent duplicates.
    const existingAchievements: Array<Record<string, unknown>> =
      newData.achievements || [];
    const earnedIds = new Set<string>(
      existingAchievements.map((a) => a.id as string),
    );

    const awardable = computeAwardableAchievements(
      newStats, earnedIds, thresholds,
    );
    if (awardable.length === 0) return;

    // Concrete timestamp, NOT serverTimestamp() — Firestore rejects the
    // serverTimestamp() sentinel inside array elements (arrayUnion), which
    // threw the whole award write before, so nothing was ever persisted.
    const toAward = awardable.map((a) => ({
      ...a, earnedAt: admin.firestore.Timestamp.now(),
    }));

    // Write all new achievements in a single update.
    await event.data.after.ref.update({
      achievements: admin.firestore.FieldValue.arrayUnion(...toAward),
    });

    functions.logger.info("Achievements awarded", {
      awarded: toAward.map((a) => a.id),
    });

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
          functions.logger.info("Achievement notification sent");
        } catch (error) {
          functions.logger.error("Failed to send achievement notification", {
            errorCode: errorCodeForLog(error),
          });
        }
      }
    }

    return;
  });

/**
 * Notifies parents when a student is newly awarded — either the weekly Top
 * Reader (`autoAward`, written by topReaderAward) or a teacher's special award
 * (`manualAward`, written client-side by the teacher). Fires on any student-doc
 * update but only acts when an award's identity actually changes (newly added
 * or refreshed for a new week), so unrelated writes (stats, achievements,
 * character picks) don't re-notify. For each linked parent it (1) creates an
 * inbox item — so the award appears in the notifications list + badge and
 * survives reinstalls — and (2) sends a push. The app also shows a celebration
 * modal on next open, driven by the live award fields.
 *
 * This trigger never writes the student doc, so it cannot self-trigger.
 */
export const notifyAwardChanges = onDocumentUpdated(
  {document: "schools/{schoolId}/students/{studentId}", concurrency: 1},
  async (event) => {
    if (!event.data) return;
    const schoolId = event.params.schoolId;
    const studentId = event.params.studentId;
    const before = event.data.before.data() || {};
    const after = event.data.after.data();
    if (!after) return;

    const parentIds: string[] =
      Array.isArray(after.parentIds) ? after.parentIds : [];
    if (parentIds.length === 0) return;

    const firstName = (after.firstName as string) || "Your child";

    // One entry per award type that was newly assigned / refreshed.
    const awardEvents: Array<{
      type: "auto" | "manual";
      dedupeId: string;
      title: string;
      body: string;
    }> = [];

    if (awardChanged(before.autoAward, after.autoAward)) {
      const name = (after.autoAward?.name as string) || "Reader of the Week";
      awardEvents.push({
        type: "auto",
        dedupeId: `auto_${awardDedupe(after.autoAward)}`,
        title: `${firstName} is ${name}! 🏆`,
        body:
          `${firstName} read the most minutes in class last week. ` +
          "Cheer them on to keep it up!",
      });
    }

    if (awardChanged(before.manualAward, after.manualAward)) {
      const name = (after.manualAward?.name as string) || "a special award";
      awardEvents.push({
        type: "manual",
        dedupeId: `manual_${awardDedupe(after.manualAward)}`,
        title: `${firstName} earned an award! 🌟`,
        body:
          `${firstName}'s teacher gave them the "${name}" award. ` +
          "Celebrate their reading!",
      });
    }

    if (awardEvents.length === 0) return;

    for (const awardEvent of awardEvents) {
      for (const parentId of parentIds) {
        try {
          const parentRef = db.doc(
            `schools/${schoolId}/parents/${parentId}`,
          );
          const parentSnap = await parentRef.get();
          if (!parentSnap.exists) continue;

          // Deterministic inbox id → a rare re-fire merges instead of dupes.
          const inboxId = `award_${studentId}_${awardEvent.dedupeId}`;
          await parentRef.collection("notifications").doc(inboxId).set({
            campaignId: inboxId,
            schoolId,
            title: awardEvent.title,
            body: awardEvent.body,
            messageType: "award",
            studentIds: [studentId],
            classIds: [],
            senderName: "Lumi",
            senderRole: "system",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
            pushStatus: "pending",
            isRead: false,
            readAt: null,
          }, {merge: true});

          const fcmToken = parentSnap.data()?.fcmToken;
          if (!fcmToken) continue;
          await admin.messaging().send({
            token: fcmToken,
            notification: {title: awardEvent.title, body: awardEvent.body},
            data: {
              type: "award_earned",
              studentId,
              schoolId,
              awardType: awardEvent.type,
            },
          });
          functions.logger.info("Award notification sent", {
            awardType: awardEvent.type,
          });
        } catch (error) {
          functions.logger.error("Failed to send award notification", {
            errorCode: errorCodeForLog(error),
          });
        }
      }
    }

    return;
  });

// True when `after` holds an award whose identity differs from `before` — i.e.
// a newly assigned award, or the same award refreshed for a new week. Removals
// (award present in `before`, absent in `after`) and unchanged awards return
// false, so we only ever celebrate additions.
function awardChanged(
  before: Record<string, unknown> | undefined,
  after: Record<string, unknown> | undefined,
): boolean {
  if (!after) return false;
  const beforeKey = before ? awardIdentity(before) : null;
  return beforeKey !== awardIdentity(after);
}

function awardIdentity(award: Record<string, unknown>): string {
  const characterId = (award.characterId as string) || "";
  const name = (award.name as string) || "";
  const weekOf = (award.weekOf as string) || "";
  return `${characterId}|${name}|${weekOf}|${awardDedupe(award)}`;
}

// Stable per-award key: week-of for the weekly award, else its awardedAt.
function awardDedupe(award: Record<string, unknown> | undefined): string {
  if (!award) return "unknown";
  const weekOf = award.weekOf as string | undefined;
  if (weekOf) return weekOf;
  const awardedAt = award.awardedAt as {toMillis?: () => number} | undefined;
  if (awardedAt && typeof awardedAt.toMillis === "function") {
    return String(awardedAt.toMillis());
  }
  return (award.name as string) || "award";
}

/**
 * Backfill achievements (admin-gated, idempotent).
 *
 * Awards every achievement each student currently qualifies for based on their
 * existing stats — WITHOUT sending notifications. Use after launch / data
 * migrations so students who reached thresholds before the idempotent detector
 * existed (or whose stats were imported/recomputed) get their badges without
 * waiting for their next reading log. Safe to re-run; never double-awards.
 *
 * Params: `{ schoolId: string, studentId?: string }`. Omit studentId to process
 * the whole school. Caller must be a schoolAdmin of that school.
 */
export const backfillAchievements = onCall(async (request) => {
  const data = request.data;
  assertNotReadOnly(request);
  if (!request.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated", "Must be signed in.",
    );
  }
  const {schoolId, studentId} = (data ?? {}) as {
    schoolId?: string; studentId?: string;
  };
  if (!schoolId) {
    throw new functions.https.HttpsError(
      "invalid-argument", "schoolId is required.",
    );
  }

  const callerDoc = await db
    .doc(`schools/${schoolId}/users/${request.auth.uid}`)
    .get();
  if (!callerDoc.exists || callerDoc.data()?.role !== "schoolAdmin") {
    throw new functions.https.HttpsError(
      "permission-denied", "Only a school admin can run the backfill.",
    );
  }

  const thresholds = await resolveAchievementThresholds(schoolId);
  const studentsRef = db.collection(`schools/${schoolId}/students`);
  const docs = studentId ?
    [await studentsRef.doc(studentId).get()].filter((d) => d.exists) :
    (await studentsRef.get()).docs;

  let studentsProcessed = 0;
  let studentsUpdated = 0;
  let achievementsAwarded = 0;
  for (const doc of docs) {
    studentsProcessed++;
    const sData = doc.data() ?? {};
    const stats = (sData.stats || {}) as Record<string, unknown>;
    const existing: Array<Record<string, unknown>> = sData.achievements || [];
    const earnedIds = new Set<string>(existing.map((a) => a.id as string));
    const awardable = computeAwardableAchievements(stats, earnedIds, thresholds);
    if (awardable.length === 0) continue;
    // Concrete timestamp, NOT serverTimestamp() — Firestore rejects the
    // serverTimestamp() sentinel inside array elements (arrayUnion), which
    // threw the whole award write before, so nothing was ever persisted.
    const toAward = awardable.map((a) => ({
      ...a, earnedAt: admin.firestore.Timestamp.now(),
    }));
    try {
      await doc.ref.update({
        achievements: admin.firestore.FieldValue.arrayUnion(...toAward),
      });
      studentsUpdated++;
      achievementsAwarded += toAward.length;
    } catch (err) {
      functions.logger.warn("backfillAchievements: student update failed", {
        errorCode: errorCodeForLog(err),
      });
    }
  }

  functions.logger.info("backfillAchievements complete", {
    studentsProcessed, studentsUpdated, achievementsAwarded,
  });
  return {success: true, studentsProcessed, studentsUpdated, achievementsAwarded};
});

/**
 * Validate Reading Log
 * Server-side validation before allowing log creation
 */
export const validateReadingLog = onDocumentCreated(
  {document: "schools/{schoolId}/readingLogs/{logId}", concurrency: 1},
  async (event) => {
    if (!event.data) return;
    const schoolId = event.params.schoolId;
    const logData = event.data.data();

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

    // Validate parent has permission. Teacher-proxy logs intentionally store the
    // teacher's uid in `parentId` (loggedByRole === "teacher"), so the
    // guardian-link check doesn't apply to them.
    const studentData = studentDoc.data();
    const isTeacherProxy = logData.loggedByRole === "teacher";
    const parentLinked = studentData?.parentIds?.includes(logData.parentId);
    if (!isTeacherProxy && studentData && !parentLinked) {
      validationErrors.push("Parent not linked to this student");
    }

    // If validation fails, mark the log as invalid. Valid logs get NO write:
    // absence of validationStatus means valid everywhere (isInvalidatedLog
    // keys on === "invalid"; nothing reads "valid"/validatedAt), and the old
    // valid-stamp update re-fired both stats triggers on every single log —
    // a wasted write + double aggregation for the ~all-valid majority.
    if (validationErrors.length > 0) {
      await event.data.ref.update({
        validationStatus: "invalid",
        validationErrors: validationErrors,
      });

      functions.logger.warn("Invalid reading log detected", {
        errors: validationErrors,
      });
    }

    return;
  });

/**
 * Clean up expired link codes
 * Runs daily to remove old codes
 */
export const cleanupExpiredLinkCodes = onSchedule(
  {
    schedule: "0 2 * * *", // 2 AM daily
    // PRESERVE the Gen1 effective timezone exactly. This job had no explicit
    // .timeZone(), so its deployed Cloud Scheduler job runs in
    // America/Los_Angeles (the v1 default). Setting it here keeps the run time
    // unchanged — Gen2 onSchedule would otherwise use a different default.
    timeZone: "America/Los_Angeles",
  },
  async () => {
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

      await recordCronRun("cleanupExpiredLinkCodes", "ok");
      return;
    } catch (error) {
      functions.logger.error("Error cleaning up expired codes", {
        errorCode: errorCodeForLog(error),
      });
      await recordCronRun("cleanupExpiredLinkCodes", "error",
        errorCodeForLog(error));
      throw error;
    }
  });

/**
 * Update class statistics when allocations or logs change
 */
// ─── Parent Onboarding Emails ───────────────────────────────────────────

const LINK_CODE_CHARS = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const LINK_CODE_LENGTH = 8;
const LINK_CODE_EXPIRY_DAYS = 30;

function generateLinkCode(): string {
  let code = "";
  for (let i = 0; i < LINK_CODE_LENGTH; i++) {
    code += LINK_CODE_CHARS.charAt(crypto.randomInt(LINK_CODE_CHARS.length));
  }
  return code;
}

async function getOrCreateLinkCode(
  studentId: string,
  schoolId: string,
  createdBy: string,
  studentName: string,
): Promise<string> {
  // Defensive: refuse to mint or return a code for a non-existent student.
  // Without this guard an orphan code can outlive the student doc, and
  // parents who try to use it later hit "student-missing" from
  // linkParentToStudent with no way forward.
  const studentSnap = await db
    .collection("schools").doc(schoolId)
    .collection("students").doc(studentId)
    .get();
  if (!studentSnap.exists) {
    throw new Error(
      `getOrCreateLinkCode: student ${schoolId}/${studentId} does not exist`,
    );
  }

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

export const processParentOnboardingEmail = onDocumentCreated(
  {
    document: "schools/{schoolId}/parentOnboardingEmails/{emailId}",
    concurrency: 1,
    timeoutSeconds: 120,
    memory: "512MiB",
    secrets: [sendgridApiKey, sendgridSenderEmail],
  },
  async (event) => {
    if (!event.data) return;
    const data = event.data.data();
    if (data.status !== "queued") return;

    const schoolId = event.params.schoolId;
    const docRef = event.data.ref;

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
        return;
      }
      sgMail.setApiKey(sendgridKey);

      // Fetch school
      const schoolSnap = await db.doc(`schools/${schoolId}`).get();
      const schoolName = schoolSnap.data()?.name ?? "Your School";
      // Whole-school-paid schools cover every rostered student, so the
      // enrollmentStatus "not_enrolled" skip below must not apply to them.
      const wholeSchoolPaid =
        (schoolSnap.data()?.accessMode ?? "whole_school_paid") ===
        "whole_school_paid";

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
          if (!wholeSchoolPaid && !isSubscribed) {
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
          // Inline images: the Lumi mascot (hero) + one QR per child.
          const attachments = [
            lumiMascotAttachment(),
            ...(await buildOnboardingQrAttachments(entries)),
          ];
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
          functions.logger.error("Parent onboarding email send failed", {
            errorCode: errorCodeForLog(err),
          });
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

      functions.logger.info("Parent onboarding email batch complete", {
        sent: sentCount,
        failed: failedCount,
        skipped: skippedCount,
      });
    } catch (error) {
      functions.logger.error("processParentOnboardingEmail failed", {
        errorCode: errorCodeForLog(error),
      });
      await docRef.update({
        status: "failed",
        errorSummary: error instanceof Error ? error.message : String(error),
      });
    }

    return;
  });

// URL of the school admin portal (Firebase Hosting "school" target).
// Override with the STAFF_PORTAL_URL env var if the domain changes.
const STAFF_PORTAL_URL =
  process.env.STAFF_PORTAL_URL || "https://lumi-school-admin.web.app";

interface StaffEmailRecipient {
  userId: string;
  email: string;
  status: "sent" | "failed" | "skipped";
  error?: string;
  skippedReason?: string;
}

export const processStaffOnboardingEmail = onDocumentCreated(
  {
    document: "schools/{schoolId}/staffOnboardingEmails/{emailId}",
    concurrency: 1,
    timeoutSeconds: 120,
    memory: "512MiB",
    secrets: [sendgridApiKey, sendgridSenderEmail],
  },
  async (event) => {
    if (!event.data) return;
    const data = event.data.data();
    if (data.status !== "queued") return;

    const schoolId = event.params.schoolId;
    const docRef = event.data.ref;

    // Claim the document
    await docRef.update({status: "processing"});

    try {
      const sendgridKey = sendgridApiKey.value();
      if (!sendgridKey) {
        await docRef.update({
          status: "failed",
          errorSummary: "SendGrid API key not configured",
        });
        return;
      }
      sgMail.setApiKey(sendgridKey);

      const schoolSnap = await db.doc(`schools/${schoolId}`).get();
      const schoolName = schoolSnap.data()?.name ?? "Your School";

      const targetUserIds: string[] = data.targetUserIds ?? [];
      const customMessage: string | undefined = data.customMessage ?? undefined;
      const emailSubject = data.emailSubject ?? `Your ${schoolName} staff account on Lumi`;
      const senderEmail = sendgridSenderEmail.value() || "noreply@lumi-reading.app";

      // The school's active join code (top-level schoolCodes; one active per
      // school) — teachers enter it in the Lumi app to join. Omitted if none.
      const codeSnap = await db.collection("schoolCodes").where("schoolId", "==", schoolId).get();
      const schoolCode: string | undefined = codeSnap.docs
        .map((d) => d.data())
        .filter((d) => d.isActive === true)
        .sort((a, b) => (b.createdAt?.toMillis?.() ?? 0) - (a.createdAt?.toMillis?.() ?? 0))[0]?.code;

      const recipients: StaffEmailRecipient[] = [];
      let sentCount = 0;
      let failedCount = 0;
      let skippedCount = 0;

      for (const userBatch of chunk(targetUserIds, FIRESTORE_IN_LIMIT)) {
        const userRefs = userBatch.map((id) => db.doc(`schools/${schoolId}/users/${id}`));
        const credRefs = userBatch.map((id) => db.doc(`schools/${schoolId}/staffCredentials/${id}`));
        const [userSnaps, credSnaps] = await Promise.all([
          db.getAll(...userRefs),
          db.getAll(...credRefs),
        ]);

        for (let i = 0; i < userSnaps.length; i++) {
          const userSnap = userSnaps[i];
          const credSnap = credSnaps[i];
          const userId = userBatch[i];

          if (!userSnap.exists) {
            recipients.push({userId, email: "", status: "skipped", skippedReason: "user_not_found"});
            skippedCount++;
            continue;
          }
          const user = userSnap.data()!;
          const email: string = user.email ?? "";

          if (!email) {
            recipients.push({userId, email: "", status: "skipped", skippedReason: "no_email"});
            skippedCount++;
            continue;
          }

          // Include a sign-in password only for an admin-created account
          // (createdBy set) that hasn't signed in yet — so we never email a
          // password the teacher has already replaced. Use the stored credential
          // if present (matches what the admin saw); otherwise issue a fresh one
          // now (covers single Add-Staff, which doesn't pre-store one).
          const createdByAdmin = !!user.createdBy;
          const hasLoggedIn = !!user.lastLoginAt;
          let tempPassword: string | undefined;
          if (createdByAdmin && !hasLoggedIn) {
            const stored: string | undefined = credSnap.exists ? credSnap.data()?.tempPassword : undefined;
            if (stored) {
              tempPassword = stored;
            } else {
              const fresh = generateTempPassword();
              await admin.auth().updateUser(userId, {password: fresh});
              await db.doc(`schools/${schoolId}/staffCredentials/${userId}`).set({
                tempPassword: fresh,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                createdBy: data.createdBy ?? "system",
                consumedAt: null,
              }, {merge: true});
              await db.doc(`schools/${schoolId}/users/${userId}`).set({
                mustChangePassword: true,
                tempPasswordCreatedAt: admin.firestore.FieldValue.serverTimestamp(),
              }, {merge: true});
              tempPassword = fresh;
            }
          }

          const html = buildStaffOnboardingEmail({
            schoolName,
            staffName: user.fullName ?? email,
            role: user.role === "schoolAdmin" ? "schoolAdmin" : "teacher",
            loginEmail: email,
            tempPassword,
            schoolCode,
            portalUrl: STAFF_PORTAL_URL,
            customMessage,
          });

          try {
            await sgMail.send({
              to: email,
              from: {email: senderEmail, name: `${schoolName} via Lumi`},
              subject: emailSubject,
              html,
              attachments: [lumiMascotAttachment()],
            });
            recipients.push({userId, email, status: "sent"});
            sentCount++;
          } catch (err) {
            const errMsg = err instanceof Error ? err.message : String(err);
            functions.logger.error("Staff onboarding email send failed", {
              errorCode: errorCodeForLog(err),
            });
            recipients.push({userId, email, status: "failed", error: errMsg});
            failedCount++;
          }
        }
      }

      let finalStatus = "failed";
      if (failedCount === 0 && sentCount > 0) {
        finalStatus = "sent";
      } else if (sentCount > 0 && failedCount > 0) {
        finalStatus = "partial";
      } else if (sentCount === 0 && skippedCount > 0 && failedCount === 0) {
        finalStatus = "sent";
      }

      await docRef.update({
        status: finalStatus,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        recipientCount: recipients.length,
        deliveryCounts: {sent: sentCount, failed: failedCount, skipped: skippedCount},
        recipients: recipients.map((r) => ({
          userId: r.userId,
          email: r.email,
          status: r.status,
          ...(r.error && {error: r.error}),
          ...(r.skippedReason && {skippedReason: r.skippedReason}),
        })),
      });

      functions.logger.info("Staff onboarding email batch complete", {
        sent: sentCount,
        failed: failedCount,
        skipped: skippedCount,
      });
    } catch (error) {
      functions.logger.error("processStaffOnboardingEmail failed", {
        errorCode: errorCodeForLog(error),
      });
      await docRef.update({
        status: "failed",
        errorSummary: error instanceof Error ? error.message : String(error),
      });
    }

    return;
  });

export const updateClassStats = onDocumentWritten(
  {document: "schools/{schoolId}/readingLogs/{logId}", concurrency: 1},
  async (event) => {
    if (!event.data) return;
    // Metadata-only updates (validation stamps, teacher-comment mirrors)
    // can't change any stat — skip before spending a single read.
    if (isStatsNoopUpdate(event.data)) return;
    const schoolId = event.params.schoolId;

    // Incremental path: read the class doc once, apply per-log delta. Old
    // code reads every counted log for every student in the class on every
    // write — fine at Pilot scale, catastrophic above. Flag defaults off.
    const incremental = await readIncrementalConfig();
    if (incremental.classStats) {
      try {
        await applyClassStatsDelta(event.data, schoolId);
      } catch (err) {
        functions.logger.error("applyClassStatsDelta failed", {
          errorCode: errorCodeForLog(err),
        });
        throw err;
      }
      return;
    }

    // Legacy full-recompute path below.
    const log = event.data.after.exists ? event.data.after.data() : null;

    if (!log) return;

    const studentDoc = await db
      .doc(`schools/${schoolId}/students/${log.studentId}`)
      .get();

    const studentData = studentDoc.data();
    if (!studentData?.classId) return;

    const classId = studentData.classId;

    // Get student IDs from the class document
    const classDoc = await db.doc(`schools/${schoolId}/classes/${classId}`).get();
    if (!classDoc.exists) return;

    const classData = classDoc.data() ?? {};
    const classStudentIds: string[] = Array.isArray(classData.studentIds) ?
      classData.studentIds.filter((id: unknown): id is string => typeof id === "string") :
      [];

    if (classStudentIds.length === 0) return;

    // Aggregate class stats — batch in chunks of 30 (Firestore `in` limit)
    let totalMinutes = 0;
    let totalBooks = 0;
    const uniqueStudents = new Set<string>();

    for (const studentBatch of classAggregationStudentBatches(classStudentIds)) {
      const logsSnapshot = await db
        .collection(`schools/${schoolId}/readingLogs`)
        .where("studentId", "in", studentBatch)
        .where("status", "in", ["completed", "partial"])
        .get();

      logsSnapshot.docs.forEach((doc) => {
        const logData = doc.data();
        if (isInvalidatedLog(logData)) return;
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

    return;
  });

/**
 * Weekly safety net for the incremental student + class stats triggers.
 * Iterates every school and runs the authoritative full-recompute path for
 * each student and class. Errors per-doc are logged and skipped so a single
 * bad doc can't halt the pass.
 *
 * Budgets keep the run inside the 540s timeout — at Large scale (~100K
 * students) this only reconciles the first 5K each Sunday; raise the
 * budgets or shard by school once monitoring tells us drift is rare.
 */
export const reconcileStatsScheduled = onSchedule(
  {
    schedule: "0 3 * * 0", // Sunday 03:00 UTC
    timeZone: "UTC",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    try {
      const result = await runReconcilePass({
        studentBudget: 5000,
        classBudget: 1000,
      });
      functions.logger.info("Stats reconcile pass complete", result);
      await recordCronRun("reconcileStatsScheduled", "ok");
    } catch (err) {
      functions.logger.error("Stats reconcile pass failed", {
        errorCode: errorCodeForLog(err),
      });
      await recordCronRun("reconcileStatsScheduled", "error",
        errorCodeForLog(err));
      throw err;
    }
    return;
  });

/**
 * Daily state term-dates fallback: fills any term slot a school hasn't
 * (validly) entered for its current local year from the official state
 * dates, resolved via the school's address. Custom same-year (or
 * future-year) entries are never touched. Runs 45 minutes before
 * refreshStreaksDaily so freshly filled dates feed the same morning's
 * streak recompute. See term_dates_fallback.ts.
 */
export const applyStateTermDates = onSchedule(
  {
    schedule: "45 3 * * *",
    timeZone: "Australia/Sydney",
    timeoutSeconds: 300,
    memory: "256MiB",
  },
  async () => {
    try {
      const result = await runStateTermDatesFillPass();
      functions.logger.info("State term-dates fill complete", result);
      await recordCronRun("applyStateTermDates", "ok",
        result.missingYearsNote ?? undefined);
    } catch (err) {
      functions.logger.error("State term-dates fill failed", {
        errorCode: errorCodeForLog(err),
      });
      await recordCronRun("applyStateTermDates", "error",
        errorCodeForLog(err));
      throw err;
    }
    return;
  });

/**
 * Daily refresh of the day-sensitive student stats (currentStreak,
 * restDaysRemaining, last30/last50 counts). Those fields are otherwise only
 * recomputed on a log write or the weekly reconcile, so a streak that dies
 * mid-week keeps displaying until Sunday. See streak_refresh.ts.
 *
 * 04:30 Sydney is past midnight in every Australian timezone year-round, so
 * each school's "today" is already the new local day when it runs.
 */
export const refreshStreaksDaily = onSchedule(
  {
    schedule: "30 4 * * *",
    timeZone: "Australia/Sydney",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    try {
      const result = await runStreakRefreshPass();
      functions.logger.info("Daily streak refresh complete", result);
      await recordCronRun("refreshStreaksDaily", "ok");
    } catch (err) {
      functions.logger.error("Daily streak refresh failed", {
        errorCode: errorCodeForLog(err),
      });
      await recordCronRun("refreshStreaksDaily", "error",
        errorCodeForLog(err));
      throw err;
    }
    return;
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
export const syncGuardianProfiles = onDocumentWritten(
  {document: "schools/{schoolId}/parents/{parentId}", concurrency: 1},
  async (event) => {
    if (!event.data) return;
    const schoolId = event.params.schoolId;
    const parentId = event.params.parentId;

    const before = event.data.before.exists ? event.data.before.data()! : null;
    const after = event.data.after.exists ? event.data.after.data()! : null;

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
        return;
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
      functions.logger.warn("syncGuardianProfiles: partial failure", {
        errorCode: errorCodeForLog(err),
      });
    }
    return;
  });

/**
 * Companion to syncGuardianProfiles. Fires on student-doc writes; when
 * `parentIds` changes (a guardian linked or unlinked), it (re)writes the
 * guardianProfiles entry for every currently-linked parent — including
 * parents whose own doc was not touched, e.g. the original guardian when a
 * co-parent is added. Loop-safe: writing guardianProfiles does not change
 * parentIds, so the re-trigger sees no change and no-ops.
 */
export const refreshGuardianProfilesOnLink = onDocumentWritten(
  {document: "schools/{schoolId}/students/{studentId}", concurrency: 1},
  async (event) => {
    if (!event.data) return;
    const schoolId = event.params.schoolId;

    const before = event.data.before.exists ? event.data.before.data()! : null;
    const after = event.data.after.exists ? event.data.after.data()! : null;
    if (!after) return; // Student deleted — nothing to maintain.

    const beforeParents: string[] = before?.parentIds ?? [];
    const afterParents: string[] = after.parentIds ?? [];

    // React only when the parent set actually changed. This also makes this
    // function's own guardianProfiles write a no-op (parentIds unchanged).
    const sameParents =
      beforeParents.length === afterParents.length &&
      beforeParents.every((id) => afterParents.includes(id));
    if (sameParents) return;

    const studentRef = event.data.after.ref;
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
      functions.logger.warn("refreshGuardianProfilesOnLink failed", {
        errorCode: errorCodeForLog(err),
      });
    }
    return;
  });

/**
 * Admin-only one-off backfill for `guardianProfiles`. Iterates every parent in
 * the given school and writes their projection onto each linked student. Safe
 * to re-run — writes are idempotent.
 */
export const backfillGuardianProfiles = onCall(
  async (request) => {
    const data = request.data;
    assertNotReadOnly(request);
    if (!request.auth) {
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
      .doc(`schools/${schoolId}/users/${request.auth.uid}`)
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
        functions.logger.warn("backfillGuardianProfiles: parent update failed", {
          errorCode: errorCodeForLog(err),
        });
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
export const onCommentCreated = onDocumentCreated(
  {document: "schools/{schoolId}/readingLogs/{logId}/comments/{commentId}", concurrency: 1},
  async (event) => {
    if (!event.data) return;
    const {schoolId, logId} = event.params as {
      schoolId: string;
      logId: string;
    };
    const comment = event.data.data() ?? {};

    // Only teacher comments drive a push; parent replies show as an in-app
    // badge (no staff tokens exist yet).
    if (comment.authorRole !== "teacher") return;

    const logRef = event.data.ref.parent.parent;
    if (!logRef) return;

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
    if (!parentId) return;

    // Teacher-proxy logs store the teacher's own UID in `parentId`. If the
    // recipient is the comment author, there's no real parent to notify.
    if (parentId === comment.authorId) return;

    const parentSnap = await db
      .doc(`schools/${schoolId}/parents/${parentId}`)
      .get();
    if (!parentSnap.exists) return;
    const parentData = parentSnap.data() ?? {};
    if (parentData.isActive === false) return;

    const pushEnabled =
      parentData.preferences?.pushNotificationsEnabled !== false;
    const token =
      typeof parentData.fcmToken === "string" ? parentData.fcmToken : undefined;
    if (!pushEnabled || !token) return;

    // Respect the school's quiet hours (the thread + badge still land; only the
    // push is suppressed).
    const schoolSnap = await db.doc(`schools/${schoolId}`).get();
    const schoolData = schoolSnap.data() ?? {};
    const timezone = String(schoolData.timezone ?? "UTC");
    if (isWithinQuietHours(new Date(), timezone, schoolData.quietHours)) {
      functions.logger.info("Comment push suppressed by quiet hours", {
        suppressed: true,
      });
      return;
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
      functions.logger.info("Comment notification sent");
    } catch (error) {
      functions.logger.error("Failed to send comment notification", {
        errorCode: errorCodeForLog(error),
      });
    }

    return;
  });

// ─────────────────────────────────────────────────────────────────────────────
// Callable: sendTestReadingReminder
// Sends a real FCM reading-reminder push to the calling parent's own device, so
// the "Send test" button exercises the full pipeline (token + delivery + the
// reading_reminder tap routing) — not just a local notification. Returns
// {sent:false} when there's no token, so the client can fall back to a local
// preview. Mirrors the body grammar of the scheduled sendReadingReminders.
// ─────────────────────────────────────────────────────────────────────────────
export const sendTestReadingReminder = onCall(
  {timeoutSeconds: 30, memory: "256MiB"},
  async (request) => {
    assertNotReadOnly(request);
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated", "Sign-in required.");
    }
    const uid = request.auth.uid;
    const data = request.data;
    const schoolId = typeof data?.schoolId === "string" ? data.schoolId : "";
    if (schoolId.length === 0) {
      throw new HttpsError(
        "invalid-argument", "schoolId is required.");
    }

    const parentSnap = await db
      .collection("schools").doc(schoolId)
      .collection("parents").doc(uid)
      .get();
    if (!parentSnap.exists) {
      throw new HttpsError(
        "not-found", "Parent profile not found.");
    }
    const parent = parentSnap.data() ?? {};
    const token = parent.fcmToken as string | undefined;
    // No push token registered on this device — let the client show a local
    // preview instead. Not an error: it's the expected fallback path.
    if (!token) return {sent: false, reason: "no-token"};

    const childIds: string[] = Array.isArray(parent.linkedChildren) ?
      (parent.linkedChildren as string[]) : [];

    // Resolve first names for the body. A test names every linked child (so it
    // always shows something), using the same grammar as the real reminder.
    const names: string[] = [];
    for (const cid of childIds) {
      const sdoc = await db
        .collection("schools").doc(schoolId)
        .collection("students").doc(cid)
        .get();
      if (sdoc.exists) {
        names.push((sdoc.data()?.firstName as string) || "your child");
      }
    }
    let who: string;
    if (names.length === 0) {
      who = "your child";
    } else if (names.length === 1) {
      who = names[0];
    } else if (names.length === 2) {
      who = `${names[0]} and ${names[1]}`;
    } else {
      who = `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`;
    }
    const body = `Don't forget to log ${who}'s reading today!`;

    try {
      await admin.messaging().send({
        token,
        notification: {title: "Time to read with Lumi! 📚", body},
        data: {
          type: "reading_reminder",
          schoolId,
          studentIds: childIds.join(","),
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
      return {sent: true};
    } catch (e) {
      functions.logger.warn("sendTestReadingReminder send failed", {
        errorCode: errorCodeForLog(e),
      });
      // Stale/invalid token — fall back to a local preview on the client.
      return {sent: false, reason: "send-failed"};
    }
  });
