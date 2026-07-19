import * as crypto from "crypto";
import * as admin from "firebase-admin";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {CallableOptions, HttpsError, onCall} from "firebase-functions/v2/https";
import {assertNotReadOnly} from "./read_only_guard";
import {recordCronRun} from "./ops_heartbeat";

const APP_CHECK_ENFORCED =
  process.env.DELETION_APP_CHECK_ENFORCED === "true";
const RECENT_AUTH_SECONDS = 30 * 60;
const MAX_JOB_ATTEMPTS = 5;
const JOB_LEASE_MS = 10 * 60 * 1000;
const JOB_RECEIPT_RETENTION_MS = 90 * 24 * 60 * 60 * 1000;
const DELETED_ACCOUNT = "deleted_account";

type DeletionKind = "account" | "student";
type DeletionStatus =
  | "pending"
  | "processing"
  | "failed"
  | "completed";

interface DeletionJob {
  kind: DeletionKind;
  status: DeletionStatus;
  requesterUid?: string;
  requesterHash: string;
  schoolId?: string;
  studentId?: string;
  requestedAt?: admin.firestore.Timestamp;
  scheduledDeletionAt?: admin.firestore.Timestamp;
  startedAt?: admin.firestore.Timestamp;
  leaseExpiresAt?: admin.firestore.Timestamp;
  nextAttemptAt?: admin.firestore.Timestamp;
  completedAt?: admin.firestore.Timestamp;
  attemptCount?: number;
  counts?: Record<string, number>;
  errorCode?: string;
}

export interface PublicDeletionStatus {
  jobId: string;
  kind: DeletionKind;
  status: DeletionStatus;
  requestedAt: string | null;
  scheduledDeletionAt: string | null;
  startedAt: string | null;
  completedAt: string | null;
  attemptCount: number;
  retrying: boolean;
}

type Counts = Record<string, number>;

function deletionRuntime(
  options: Pick<CallableOptions, "timeoutSeconds" | "memory">
): CallableOptions {
  return {
    ...options,
    enforceAppCheck: APP_CHECK_ENFORCED,
    consumeAppCheckToken: APP_CHECK_ENFORCED,
  };
}

function sha256(value: string): string {
  return crypto.createHash("sha256").update(value).digest("hex");
}

export function accountDeletionJobId(uid: string): string {
  return `account_${sha256(uid)}`;
}

export function studentDeletionJobId(
  schoolId: string,
  studentId: string
): string {
  return `student_${sha256(`${schoolId}:${studentId}`)}`;
}

function asNonEmptyString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  const result = value.trim();
  if (result.length > 200) {
    throw new HttpsError(
      "invalid-argument",
      `${field} must be 200 characters or fewer.`
    );
  }
  return result;
}

function requireRecentAuth(request: {
  auth?: {uid: string; token: Record<string, unknown>};
}): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "You must be signed in.");
  }
  const authTime = request.auth?.token.auth_time;
  const nowSeconds = Math.floor(Date.now() / 1000);
  if (
    typeof authTime !== "number" ||
    authTime < nowSeconds - RECENT_AUTH_SECONDS
  ) {
    throw new HttpsError(
      "failed-precondition",
      "recent-login-required"
    );
  }
  return uid;
}

function requireConfirmation(data: unknown): void {
  const confirmation =
    typeof data === "object" && data !== null ?
      (data as {confirmation?: unknown}).confirmation :
      null;
  if (confirmation !== "DELETE") {
    throw new HttpsError(
      "invalid-argument",
      "Type DELETE to confirm permanent deletion."
    );
  }
}

function iso(value: unknown): string | null {
  return value instanceof admin.firestore.Timestamp ?
    value.toDate().toISOString() :
    null;
}

export function publicDeletionStatus(
  jobId: string,
  data: DeletionJob
): PublicDeletionStatus {
  return {
    jobId,
    kind: data.kind,
    status: data.status,
    requestedAt: iso(data.requestedAt),
    scheduledDeletionAt: iso(data.scheduledDeletionAt),
    startedAt: iso(data.startedAt),
    completedAt: iso(data.completedAt),
    attemptCount: data.attemptCount ?? 0,
    retrying: data.status === "failed" &&
      (data.attemptCount ?? 0) < MAX_JOB_ATTEMPTS,
  };
}

function bump(counts: Counts, key: string, amount = 1): void {
  counts[key] = (counts[key] ?? 0) + amount;
}

function errorCode(error: unknown): string {
  if (error instanceof HttpsError) return error.code;
  if (typeof error === "object" && error !== null) {
    const code = (error as {code?: unknown}).code;
    if (typeof code === "string") return code.slice(0, 100);
  }
  return "internal";
}

async function deleteStorageFile(path: string, counts: Counts): Promise<void> {
  try {
    await admin.storage().bucket().file(path).delete({ignoreNotFound: true});
    bump(counts, "storageObjectsDeleted");
  } catch (error) {
    const code = (error as {code?: number | string}).code;
    if (code !== 404 && code !== "404") throw error;
  }
}

// AI comprehension-eval artifacts for a log: the teacher-only eval doc and
// the deny-all pipeline job. Deleted whenever the log itself is deleted.
async function deleteAiEvalArtifacts(
  schoolId: string,
  logId: string,
  counts: Counts
): Promise<void> {
  const db = admin.firestore();
  const evalRef = db.doc(`schools/${schoolId}/comprehensionEvals/${logId}`);
  if ((await evalRef.get()).exists) {
    await evalRef.delete();
    bump(counts, "aiEvalsDeleted");
  }
  const jobRef = db.doc(`aiEvalJobs/${schoolId}_${logId}`);
  if ((await jobRef.get()).exists) {
    await jobRef.delete();
    bump(counts, "aiEvalJobsDeleted");
  }
}

// De-identification counterpart: the log survives, so the eval's educational
// judgment (levels/criteria) stays with the student — but the transcript is
// derived from the same household voice recording being removed, so it goes
// too, and any pending pipeline job is dropped (its audio is gone).
async function stripAiEvalTranscript(
  schoolId: string,
  logId: string,
  counts: Counts
): Promise<void> {
  const db = admin.firestore();
  const evalRef = db.doc(`schools/${schoolId}/comprehensionEvals/${logId}`);
  const snap = await evalRef.get();
  if (snap.exists && typeof snap.data()?.transcript === "string") {
    await evalRef.update({
      transcript: admin.firestore.FieldValue.delete(),
      transcriptRemovedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    bump(counts, "aiEvalTranscriptsRemoved");
  }
  const jobRef = db.doc(`aiEvalJobs/${schoolId}_${logId}`);
  if ((await jobRef.get()).exists) {
    await jobRef.delete();
    bump(counts, "aiEvalJobsDeleted");
  }
}

async function deleteReadingLog(
  log: FirebaseFirestore.QueryDocumentSnapshot,
  counts: Counts
): Promise<void> {
  const schoolId = log.ref.parent.parent?.id;
  if (schoolId) {
    await deleteStorageFile(
      `schools/${schoolId}/comprehension_audio/${log.id}.m4a`,
      counts
    );
    await deleteStorageFile(
      `comprehension_audio_uploads/${schoolId}/${log.id}.m4a`,
      counts
    );
    await deleteAiEvalArtifacts(schoolId, log.id, counts);
  }
  await admin.firestore().recursiveDelete(log.ref);
  bump(counts, "readingLogsDeleted");
}

async function deidentifyAuthoredReadingLog(
  log: FirebaseFirestore.QueryDocumentSnapshot,
  counts: Counts
): Promise<void> {
  const schoolId = log.ref.parent.parent?.id;
  if (schoolId) {
    // Voice recordings are biometric-like child/household content and are not
    // needed to retain the core educational reading event.
    await deleteStorageFile(
      `schools/${schoolId}/comprehension_audio/${log.id}.m4a`,
      counts
    );
    await deleteStorageFile(
      `comprehension_audio_uploads/${schoolId}/${log.id}.m4a`,
      counts
    );
    await stripAiEvalTranscript(schoolId, log.id, counts);
  }
  const former = log.data().loggedByRole === "teacher" ?
    "Former staff member" : "Former guardian";
  await log.ref.update({
    parentId: DELETED_ACCOUNT,
    loggedByName: former,
    loggedByLabel: admin.firestore.FieldValue.delete(),
    notes: admin.firestore.FieldValue.delete(),
    photoUrls: admin.firestore.FieldValue.delete(),
    metadata: admin.firestore.FieldValue.delete(),
    parentComment: admin.firestore.FieldValue.delete(),
    parentCommentSelections: admin.firestore.FieldValue.delete(),
    parentCommentFreeText: admin.firestore.FieldValue.delete(),
    comprehensionAudioPath: admin.firestore.FieldValue.delete(),
    comprehensionAudioDurationSec: admin.firestore.FieldValue.delete(),
    comprehensionAudioUploaded: false,
    comprehensionAudioObjectGeneration: admin.firestore.FieldValue.delete(),
    comprehensionAudioSourceGeneration: admin.firestore.FieldValue.delete(),
    comprehensionAudioValidationVersion: admin.firestore.FieldValue.delete(),
    comprehensionAudioValidatedDurationMs: admin.firestore.FieldValue.delete(),
    comprehensionAudioSha256: admin.firestore.FieldValue.delete(),
    accountDeidentifiedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  bump(counts, "readingLogsDeidentified");
}

async function refreshCommentPreview(
  logRef: FirebaseFirestore.DocumentReference,
  counts: Counts
): Promise<void> {
  const log = await logRef.get();
  if (!log.exists) return;
  const comments = await logRef.collection("comments").get();
  const sorted = [...comments.docs].sort((a, b) => {
    const aMs = a.data().createdAt?.toMillis?.() ?? 0;
    const bMs = b.data().createdAt?.toMillis?.() ?? 0;
    return bMs - aMs;
  });
  const latest = sorted[0]?.data();
  const latestTeacher = sorted.find(
    (doc) => doc.data().authorRole === "teacher"
  )?.data();
  const updates: Record<string, unknown> = latest ? {
    lastCommentPreview: String(latest.body ?? "").slice(0, 200),
    lastCommentAt: latest.createdAt ??
      admin.firestore.FieldValue.serverTimestamp(),
    lastCommentByRole: latest.authorRole ?? null,
  } : {
    lastCommentPreview: admin.firestore.FieldValue.delete(),
    lastCommentAt: admin.firestore.FieldValue.delete(),
    lastCommentByRole: admin.firestore.FieldValue.delete(),
  };
  if (latestTeacher) {
    updates.teacherComment = String(latestTeacher.body ?? "");
    updates.commentedAt = latestTeacher.createdAt ??
      admin.firestore.FieldValue.serverTimestamp();
    updates.commentedBy = String(latestTeacher.authorName ?? "Teacher");
  } else {
    updates.teacherComment = admin.firestore.FieldValue.delete();
    updates.commentedAt = admin.firestore.FieldValue.delete();
    updates.commentedBy = admin.firestore.FieldValue.delete();
  }
  await logRef.update(updates);
  bump(counts, "commentPreviewsRebuilt");
}

async function deleteAuthoredComments(
  uid: string,
  counts: Counts
): Promise<void> {
  const db = admin.firestore();
  const comments = await db
    .collectionGroup("comments")
    .where("authorId", "==", uid)
    .get();
  const affectedLogs = new Map<string, FirebaseFirestore.DocumentReference>();
  for (const comment of comments.docs) {
    const logRef = comment.ref.parent.parent;
    if (logRef) affectedLogs.set(logRef.path, logRef);
    await comment.ref.delete();
    bump(counts, "commentsDeleted");
  }
  for (const logRef of affectedLogs.values()) {
    await refreshCommentPreview(logRef, counts);
  }
}

async function deleteMatchingDocs(
  query: FirebaseFirestore.Query,
  countKey: string,
  counts: Counts
): Promise<void> {
  const snap = await query.get();
  for (const doc of snap.docs) {
    await admin.firestore().recursiveDelete(doc.ref);
    bump(counts, countKey);
  }
}

async function removeAccountFromSchoolLogs(
  schoolId: string,
  uid: string,
  counts: Counts
): Promise<void> {
  const logs = await admin.firestore()
    .collection(`schools/${schoolId}/readingLogs`)
    .get();
  const viewedField = new admin.firestore.FieldPath("commentsViewedAt", uid);
  for (const log of logs.docs) {
    const viewed = log.data().commentsViewedAt;
    if (viewed && typeof viewed === "object" && uid in viewed) {
      await log.ref.update(
        viewedField,
        admin.firestore.FieldValue.delete()
      );
      bump(counts, "commentViewMarkersDeleted");
    }
  }
}

async function removeTeacherReferences(
  schoolId: string,
  uid: string,
  counts: Counts
): Promise<void> {
  const db = admin.firestore();
  const classes = db.collection(`schools/${schoolId}/classes`);
  const [arraySnap, primarySnap] = await Promise.all([
    classes.where("teacherIds", "array-contains", uid).get(),
    classes.where("teacherId", "==", uid).get(),
  ]);
  const docs = new Map<string, FirebaseFirestore.QueryDocumentSnapshot>();
  [...arraySnap.docs, ...primarySnap.docs].forEach(
    (doc) => docs.set(doc.id, doc)
  );
  for (const doc of docs.values()) {
    const data = doc.data();
    const remaining = Array.isArray(data.teacherIds) ?
      data.teacherIds.filter(
        (id: unknown): id is string => typeof id === "string" && id !== uid
      ) :
      [];
    const updates: Record<string, unknown> = {
      teacherIds: remaining,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (data.teacherId === uid) updates.teacherId = remaining[0] ?? "";
    if (data.assistantTeacherId === uid) {
      updates.assistantTeacherId = admin.firestore.FieldValue.delete();
    }
    await doc.ref.update(updates);
    bump(counts, "classTeacherReferencesRemoved");
  }

  const allocations = await db
    .collection(`schools/${schoolId}/allocations`)
    .where("teacherId", "==", uid)
    .get();
  for (const doc of allocations.docs) {
    await doc.ref.update({teacherId: DELETED_ACCOUNT});
    bump(counts, "allocationAuthorsDeidentified");
  }
  const groups = await db
    .collection(`schools/${schoolId}/readingGroups`)
    .where("createdBy", "==", uid)
    .get();
  for (const doc of groups.docs) {
    await doc.ref.update({createdBy: DELETED_ACCOUNT});
    bump(counts, "groupAuthorsDeidentified");
  }
  const campaigns = await db
    .collection(`schools/${schoolId}/notificationCampaigns`)
    .where("createdBy", "==", uid)
    .get();
  for (const doc of campaigns.docs) {
    await doc.ref.update({
      createdBy: DELETED_ACCOUNT,
      createdByName: "Former staff member",
    });
    bump(counts, "campaignAuthorsDeidentified");
  }
}

async function deleteMembership(
  ref: FirebaseFirestore.DocumentReference,
  counterField: "parentCount" | "teacherCount",
  counts: Counts
): Promise<void> {
  const db = admin.firestore();
  await db.runTransaction(async (tx) => {
    const current = await tx.get(ref);
    if (!current.exists) return;
    const schoolRef = ref.parent.parent;
    const school = schoolRef ? await tx.get(schoolRef) : null;
    tx.delete(ref);
    if (schoolRef) {
      const currentCount = school?.data()?.[counterField];
      if (typeof currentCount === "number" && currentCount > 0) {
        tx.update(schoolRef, {[counterField]: currentCount - 1});
      }
    }
  });
  await db.recursiveDelete(ref);
  bump(counts, "membershipsDeleted");
}

export async function deleteAccountData(uid: string): Promise<Counts> {
  const db = admin.firestore();
  const counts: Counts = {};
  let authUser: admin.auth.UserRecord | null = null;
  try {
    authUser = await admin.auth().getUser(uid);
  } catch (error) {
    if ((error as {code?: string}).code !== "auth/user-not-found") throw error;
  }

  const [allParents, allUsers] = await Promise.all([
    db.collectionGroup("parents").get(),
    db.collectionGroup("users").get(),
  ]);
  const parentMemberships = allParents.docs.filter((doc) => doc.id === uid);
  const staffMemberships = allUsers.docs.filter((doc) => doc.id === uid);
  const schoolIds = new Set<string>();

  for (const parent of parentMemberships) {
    const schoolId = parent.ref.parent.parent?.id;
    if (!schoolId) continue;
    schoolIds.add(schoolId);
    const children = Array.isArray(parent.data().linkedChildren) ?
      parent.data().linkedChildren.filter(
        (id: unknown): id is string => typeof id === "string"
      ) :
      [];
    for (const studentId of children) {
      const studentRef = db.doc(`schools/${schoolId}/students/${studentId}`);
      const student = await studentRef.get();
      if (!student.exists) continue;
      await studentRef.update(
        "parentIds",
        admin.firestore.FieldValue.arrayRemove(uid),
        new admin.firestore.FieldPath("guardianProfiles", uid),
        admin.firestore.FieldValue.delete()
      );
      bump(counts, "studentLinksRemoved");
    }
  }

  for (const staff of staffMemberships) {
    const schoolId = staff.ref.parent.parent?.id;
    if (!schoolId) continue;
    schoolIds.add(schoolId);
    await removeTeacherReferences(schoolId, uid, counts);
    await db.recursiveDelete(
      db.doc(`schools/${schoolId}/staffCredentials/${uid}`)
    );
  }

  for (const schoolId of schoolIds) {
    const logs = await db
      .collection(`schools/${schoolId}/readingLogs`)
      .where("parentId", "==", uid)
      .get();
    for (const log of logs.docs) {
      await deidentifyAuthoredReadingLog(log, counts);
    }
    await removeAccountFromSchoolLogs(schoolId, uid, counts);
  }

  await deleteAuthoredComments(uid, counts);
  for (const parent of parentMemberships) {
    await deleteMembership(parent.ref, "parentCount", counts);
  }
  for (const staff of staffMemberships) {
    await deleteMembership(staff.ref, "teacherCount", counts);
  }

  await deleteMatchingDocs(
    db.collection("userSchoolIndex").where("userId", "==", uid),
    "userIndexesDeleted",
    counts
  );
  const membershipIndex = db.doc(`userMembershipIndex/${uid}`);
  if ((await membershipIndex.get()).exists) {
    await membershipIndex.delete();
    bump(counts, "userMembershipIndexesDeleted");
  }
  await deleteMatchingDocs(
    db.collection("feedback").where("userId", "==", uid),
    "feedbackDeleted",
    counts
  );
  await deleteMatchingDocs(
    db.collection("notifications").where("userId", "==", uid),
    "notificationsDeleted",
    counts
  );
  await db.recursiveDelete(db.doc(`users/${uid}`));

  const books = await db
    .collection("community_books")
    .where("contributedBy", "==", uid)
    .get();
  for (const book of books.docs) {
    await book.ref.update({contributedBy: DELETED_ACCOUNT});
    bump(counts, "bookContributorsDeidentified");
  }
  const requests = await db
    .collectionGroup("deletionRequests")
    .where("requestedBy", "==", uid)
    .get();
  for (const request of requests.docs) {
    await request.ref.delete();
    bump(counts, "catalogRequestsDeleted");
  }

  const email = authUser?.email?.trim().toLowerCase();
  if (email) await db.doc(`devAccessEmails/${sha256(email)}`).delete();
  const phone = authUser?.phoneNumber;
  if (phone) {
    await db.doc(`smsRateLimits/${encodeURIComponent(phone)}`).delete();
  }

  try {
    await admin.auth().deleteUser(uid);
    bump(counts, "authUsersDeleted");
  } catch (error) {
    if ((error as {code?: string}).code !== "auth/user-not-found") throw error;
  }
  return counts;
}

async function removeStudentFromParentNotifications(
  studentId: string,
  counts: Counts
): Promise<void> {
  const notifications = await admin.firestore()
    .collectionGroup("notifications")
    .where("studentIds", "array-contains", studentId)
    .get();
  for (const notification of notifications.docs) {
    const current: string[] = Array.isArray(notification.data().studentIds) ?
      notification.data().studentIds.filter(
        (id: unknown): id is string => typeof id === "string"
      ) :
      [];
    const remaining = current.filter((id) => id !== studentId);
    if (remaining.length === 0) {
      await notification.ref.delete();
      bump(counts, "notificationsDeleted");
    } else {
      await notification.ref.update({studentIds: remaining});
      bump(counts, "notificationReferencesRemoved");
    }
  }
}

export async function deleteStudentData(
  schoolId: string,
  studentId: string
): Promise<Counts> {
  const db = admin.firestore();
  const counts: Counts = {};
  const studentRef = db.doc(`schools/${schoolId}/students/${studentId}`);
  const student = await studentRef.get();
  if (!student.exists) return counts;
  const studentData = student.data() ?? {};
  await studentRef.update({
    pendingDeletion: true,
    pendingDeletionAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  const parentIds = Array.isArray(studentData.parentIds) ?
    studentData.parentIds.filter(
      (id: unknown): id is string => typeof id === "string"
    ) :
    [];

  const logs = await db
    .collection(`schools/${schoolId}/readingLogs`)
    .where("studentId", "==", studentId)
    .get();
  for (const log of logs.docs) await deleteReadingLog(log, counts);

  // Safety sweep: evals/jobs whose reading log vanished through some earlier
  // path still carry the student's derived content — remove them by
  // studentId (single-field queries; jobs filtered to this school in code).
  const orphanEvals = await db
    .collection(`schools/${schoolId}/comprehensionEvals`)
    .where("studentId", "==", studentId)
    .get();
  for (const doc of orphanEvals.docs) {
    await doc.ref.delete();
    bump(counts, "aiEvalsDeleted");
  }
  const orphanJobs = await db
    .collection("aiEvalJobs")
    .where("studentId", "==", studentId)
    .get();
  for (const doc of orphanJobs.docs) {
    if (doc.data().schoolId !== schoolId) continue;
    await doc.ref.delete();
    bump(counts, "aiEvalJobsDeleted");
  }

  for (const parentId of parentIds) {
    const parentRef = db.doc(`schools/${schoolId}/parents/${parentId}`);
    const parent = await parentRef.get();
    if (!parent.exists) continue;
    await parentRef.update({
      linkedChildren: admin.firestore.FieldValue.arrayRemove(studentId),
      linkedChildrenUpdatedAt:
        admin.firestore.FieldValue.serverTimestamp(),
      linkedChildrenUpdatedBy: "system:student-deletion",
    });
    bump(counts, "parentLinksRemoved");
  }

  const classes = await db
    .collection(`schools/${schoolId}/classes`)
    .where("studentIds", "array-contains", studentId)
    .get();
  for (const doc of classes.docs) {
    await doc.ref.update({
      studentIds: admin.firestore.FieldValue.arrayRemove(studentId),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    bump(counts, "classReferencesRemoved");
  }
  const groups = await db
    .collection(`schools/${schoolId}/readingGroups`)
    .where("studentIds", "array-contains", studentId)
    .get();
  for (const doc of groups.docs) {
    await doc.ref.update({
      studentIds: admin.firestore.FieldValue.arrayRemove(studentId),
      [`studentOverrides.${studentId}`]:
        admin.firestore.FieldValue.delete(),
    });
    bump(counts, "groupReferencesRemoved");
  }
  const allocations = await db
    .collection(`schools/${schoolId}/allocations`)
    .get();
  for (const doc of allocations.docs) {
    const data = doc.data();
    const hasDirectAssignment = Array.isArray(data.studentIds) &&
      data.studentIds.includes(studentId);
    const hasOverride = data.studentOverrides &&
      typeof data.studentOverrides === "object" &&
      studentId in data.studentOverrides;
    if (!hasDirectAssignment && !hasOverride) continue;
    await doc.ref.update({
      studentIds: admin.firestore.FieldValue.arrayRemove(studentId),
      [`studentOverrides.${studentId}`]:
        admin.firestore.FieldValue.delete(),
    });
    bump(counts, "allocationReferencesRemoved");
  }
  const campaigns = await db
    .collection(`schools/${schoolId}/notificationCampaigns`)
    .where("targetStudentIds", "array-contains", studentId)
    .get();
  for (const doc of campaigns.docs) {
    await doc.ref.update({
      targetStudentIds: admin.firestore.FieldValue.arrayRemove(studentId),
    });
    bump(counts, "campaignReferencesRemoved");
  }

  await removeStudentFromParentNotifications(studentId, counts);
  await deleteMatchingDocs(
    db.collection("studentLinkCodes").where("studentId", "==", studentId),
    "linkCodesDeleted",
    counts
  );

  await db.runTransaction(async (tx) => {
    const [current, school] = await Promise.all([
      tx.get(studentRef),
      tx.get(db.doc(`schools/${schoolId}`)),
    ]);
    if (!current.exists) return;
    tx.delete(studentRef);
    const count = school.data()?.studentCount;
    // The school portal hides queued students and decrements its live count
    // immediately. Mobile requests leave isActive unchanged until this point.
    // Checking the authoritative current flag keeps both paths idempotent.
    if (current.data()?.isActive !== false &&
        typeof count === "number" && count > 0) {
      tx.update(school.ref, {studentCount: count - 1});
    }
  });
  await db.recursiveDelete(studentRef);
  bump(counts, "studentsDeleted");
  return counts;
}

async function authorizeStudentDeletion(
  uid: string,
  schoolId: string,
  studentId: string
): Promise<FirebaseFirestore.DocumentSnapshot> {
  const db = admin.firestore();
  const [staff, student] = await Promise.all([
    db.doc(`schools/${schoolId}/users/${uid}`).get(),
    db.doc(`schools/${schoolId}/students/${studentId}`).get(),
  ]);
  if (!staff.exists || staff.data()?.isActive === false) {
    throw new HttpsError("permission-denied", "Active school staff required.");
  }
  if (!student.exists) {
    throw new HttpsError("not-found", "Student not found.");
  }
  const role = staff.data()?.role;
  if (role === "schoolAdmin") return student;
  if (role !== "teacher") {
    throw new HttpsError(
      "permission-denied",
      "Only school staff can delete student data."
    );
  }
  const classId = student.data()?.classId;
  if (typeof classId !== "string" || classId.length === 0) {
    throw new HttpsError("failed-precondition", "Student has no class.");
  }
  const classDoc = await db.doc(`schools/${schoolId}/classes/${classId}`).get();
  const assigned = classDoc.exists &&
    (classDoc.data()?.teacherId === uid ||
      (Array.isArray(classDoc.data()?.teacherIds) &&
        classDoc.data()?.teacherIds.includes(uid)));
  if (!assigned) {
    throw new HttpsError(
      "permission-denied",
      "Teachers may delete data only for students in an assigned class."
    );
  }
  return student;
}

export function isDeletionJobDue(
  job: DeletionJob,
  nowMs: number
): boolean {
  if ((job.attemptCount ?? 0) >= MAX_JOB_ATTEMPTS) return false;
  if (job.status === "pending") {
    return (job.scheduledDeletionAt?.toMillis() ?? 0) <= nowMs;
  }
  if (job.status === "failed") {
    return (job.nextAttemptAt?.toMillis() ?? 0) <= nowMs;
  }
  if (job.status === "processing") {
    return (job.leaseExpiresAt?.toMillis() ?? 0) <= nowMs;
  }
  return false;
}

export async function processDeletionJob(
  jobRef: FirebaseFirestore.DocumentReference
): Promise<PublicDeletionStatus> {
  const db = admin.firestore();
  const claimed = await db.runTransaction(async (tx) => {
    const snap = await tx.get(jobRef);
    if (!snap.exists) throw new HttpsError("not-found", "Deletion job missing.");
    const job = snap.data() as DeletionJob;
    if (!isDeletionJobDue(job, Date.now())) return null;
    const attempt = (job.attemptCount ?? 0) + 1;
    tx.update(jobRef, {
      status: "processing",
      startedAt: admin.firestore.FieldValue.serverTimestamp(),
      leaseExpiresAt: admin.firestore.Timestamp.fromMillis(
        Date.now() + JOB_LEASE_MS
      ),
      attemptCount: attempt,
      errorCode: admin.firestore.FieldValue.delete(),
    });
    return {...job, status: "processing", attemptCount: attempt} as DeletionJob;
  });

  if (!claimed) {
    const current = await jobRef.get();
    return publicDeletionStatus(jobRef.id, current.data() as DeletionJob);
  }

  try {
    const counts = claimed.kind === "account" ?
      await deleteAccountData(asNonEmptyString(
        claimed.requesterUid,
        "requesterUid"
      )) :
      await deleteStudentData(
        asNonEmptyString(claimed.schoolId, "schoolId"),
        asNonEmptyString(claimed.studentId, "studentId")
      );
    await jobRef.update({
      status: "completed",
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromMillis(
        Date.now() + JOB_RECEIPT_RETENTION_MS
      ),
      counts,
      requesterUid: admin.firestore.FieldValue.delete(),
      studentId: admin.firestore.FieldValue.delete(),
      leaseExpiresAt: admin.firestore.FieldValue.delete(),
      nextAttemptAt: admin.firestore.FieldValue.delete(),
      errorCode: admin.firestore.FieldValue.delete(),
    });
  } catch (error) {
    const attempts = claimed.attemptCount ?? 1;
    const retryMinutes = Math.min(60, Math.pow(2, attempts));
    const failureUpdate: Record<string, unknown> = {
      status: "failed",
      errorCode: errorCode(error),
      nextAttemptAt: admin.firestore.Timestamp.fromMillis(
        Date.now() + retryMinutes * 60 * 1000
      ),
      leaseExpiresAt: admin.firestore.FieldValue.delete(),
    };
    if (attempts >= MAX_JOB_ATTEMPTS) {
      failureUpdate.expiresAt = admin.firestore.Timestamp.fromMillis(
        Date.now() + JOB_RECEIPT_RETENTION_MS
      );
    }
    await jobRef.update(failureUpdate);
    throw error;
  }
  const completed = await jobRef.get();
  return publicDeletionStatus(jobRef.id, completed.data() as DeletionJob);
}

export const requestAccountDeletion = onCall(
  deletionRuntime({timeoutSeconds: 540, memory: "512MiB"}),
  async (request) => {
    assertNotReadOnly(request);
    const uid = requireRecentAuth(request);
    requireConfirmation(request.data);
    const jobRef = admin.firestore()
      .collection("deletionJobs")
      .doc(accountDeletionJobId(uid));
    const existing = await jobRef.get();
    if (!existing.exists) {
      const now = admin.firestore.Timestamp.now();
      await jobRef.create({
        kind: "account",
        status: "pending",
        requesterUid: uid,
        requesterHash: sha256(uid),
        requestedAt: now,
        scheduledDeletionAt: now,
        attemptCount: 0,
        inventoryVersion: 1,
      });
    }
    return processDeletionJob(jobRef);
  }
);

export const requestStudentDeletion = onCall(
  deletionRuntime({timeoutSeconds: 540, memory: "512MiB"}),
  async (request) => {
    assertNotReadOnly(request);
    const uid = requireRecentAuth(request);
    requireConfirmation(request.data);
    const schoolId = asNonEmptyString(request.data?.schoolId, "schoolId");
    const studentId = asNonEmptyString(request.data?.studentId, "studentId");
    const confirmationName = asNonEmptyString(
      request.data?.studentName,
      "studentName"
    );
    const student = await authorizeStudentDeletion(uid, schoolId, studentId);
    const expectedName = `${student.data()?.firstName ?? ""} ${
      student.data()?.lastName ?? ""
    }`.trim();
    if (confirmationName.toLocaleLowerCase() !==
        expectedName.toLocaleLowerCase()) {
      throw new HttpsError(
        "invalid-argument",
        "The student name did not match."
      );
    }
    const jobRef = admin.firestore()
      .collection("deletionJobs")
      .doc(studentDeletionJobId(schoolId, studentId));
    const existing = await jobRef.get();
    if (!existing.exists) {
      const now = admin.firestore.Timestamp.now();
      await jobRef.create({
        kind: "student",
        status: "pending",
        requesterUid: uid,
        requesterHash: sha256(uid),
        schoolId,
        studentId,
        requestedAt: now,
        scheduledDeletionAt: now,
        attemptCount: 0,
        inventoryVersion: 1,
      });
    }
    return processDeletionJob(jobRef);
  }
);

export const getMyDeletionStatus = onCall(
  deletionRuntime({timeoutSeconds: 15, memory: "256MiB"}),
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign-in required.");
    const kind = request.data?.kind === "student" ? "student" : "account";
    const jobId = kind === "account" ?
      accountDeletionJobId(uid) :
      studentDeletionJobId(
        asNonEmptyString(request.data?.schoolId, "schoolId"),
        asNonEmptyString(request.data?.studentId, "studentId")
      );
    const job = await admin.firestore().collection("deletionJobs").doc(jobId).get();
    if (!job.exists) return {job: null};
    const data = job.data() as DeletionJob;
    if (data.requesterUid !== uid && data.requesterHash !== sha256(uid)) {
      throw new HttpsError("permission-denied", "Deletion job not accessible.");
    }
    return {job: publicDeletionStatus(job.id, data)};
  }
);

export const processPendingUserDeletions = onSchedule(
  {
    schedule: "every 5 minutes",
    timeZone: "Australia/Sydney",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    // Compatibility bridge for the school portal's existing 24-hour
    // staff-deletion/undo flow. Once due, migrate the legacy marker into the
    // same complete, resumable account job used by the mobile app. The marker
    // is retained until completion so a transient failure cannot lose work.
    const now = admin.firestore.Timestamp.now();
    const legacy = await admin.firestore()
      .collection("pendingUserDeletions")
      .where("scheduledDeletionAt", "<=", now)
      .limit(100)
      .get();
    for (const marker of legacy.docs) {
      const uid = marker.data().userId;
      if (typeof uid !== "string" || uid.length === 0) {
        console.error("Invalid legacy deletion marker", {markerId: marker.id});
        continue;
      }
      const scheduledDeletionAt = marker.data().scheduledDeletionAt instanceof
        admin.firestore.Timestamp ?
        marker.data().scheduledDeletionAt : now;
      const jobRef = admin.firestore()
        .collection("deletionJobs")
        .doc(accountDeletionJobId(uid));
      const existing = await jobRef.get();
      if (!existing.exists) {
        await jobRef.create({
          kind: "account",
          status: "pending",
          requesterUid: uid,
          requesterHash: sha256(uid),
          requestedAt: marker.data().requestedAt ?? now,
          scheduledDeletionAt,
          attemptCount: 0,
          inventoryVersion: 1,
          source: "school_portal_legacy",
        });
      }
    }

    const expired = await admin.firestore()
      .collection("deletionJobs")
      .where("expiresAt", "<=", now)
      .limit(100)
      .get();
    for (const receipt of expired.docs) await receipt.ref.delete();

    // Completed receipts are deliberately excluded so they cannot fill the
    // page and starve queued work during the 90-day evidence window.
    const jobs = await admin.firestore()
      .collection("deletionJobs")
      .where("status", "in", ["pending", "processing", "failed"])
      .limit(100)
      .get();
    let processed = 0;
    let failed = 0;
    for (const job of jobs.docs) {
      if (!isDeletionJobDue(job.data() as DeletionJob, Date.now())) continue;
      try {
        await processDeletionJob(job.ref);
        processed++;
      } catch (error) {
        failed++;
        console.error("Deletion job failed", {
          jobId: job.id,
          code: errorCode(error),
        });
      }
    }
    for (const marker of legacy.docs) {
      const uid = marker.data().userId;
      if (typeof uid !== "string" || uid.length === 0) continue;
      const job = await admin.firestore()
        .collection("deletionJobs")
        .doc(accountDeletionJobId(uid))
        .get();
      if (job.data()?.status === "completed") await marker.ref.delete();
    }
    await recordCronRun(
      "processPendingUserDeletions",
      failed === 0 ? "ok" : "error",
      `processed=${processed},failed=${failed},receiptsPurged=${expired.size}`
    );
  }
);
