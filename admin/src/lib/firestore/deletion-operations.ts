import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";

function toISO(value: unknown): string {
  if (
    value &&
    typeof value === "object" &&
    "toDate" in value &&
    typeof (value as { toDate: unknown }).toDate === "function"
  ) {
    return (value as { toDate: () => Date }).toDate().toISOString();
  }
  return "";
}

export type DeletionOperationStatus =
  | "cooling-off"
  | "pending"
  | "processing"
  | "retrying"
  | "manual-review";

export interface DeletionOperation {
  id: string;
  kind: "staff-account" | "account" | "student";
  status: DeletionOperationStatus;
  schoolId?: string;
  schoolName?: string;
  subjectName: string;
  scheduledAt: string;
  attemptCount: number;
  errorCode?: string;
  canCancel: boolean;
  canRetry: boolean;
  userId?: string;
}

function safeErrorCode(value: unknown): string | undefined {
  if (typeof value !== "string" || value.length === 0) return undefined;
  return value.replace(/[^a-zA-Z0-9_.:/-]/g, "").slice(0, 100);
}

function safeDocumentId(value: unknown): string | undefined {
  return typeof value === "string" &&
    value.length > 0 &&
    value.length <= 256 &&
    !value.includes("/")
    ? value
    : undefined;
}

export async function listDeletionOperations(): Promise<DeletionOperation[]> {
  const db = getAdminDb();
  const [markers, jobs, schools] = await Promise.all([
    db.collection("pendingUserDeletions").limit(500).get(),
    db
      .collection("deletionJobs")
      .where("status", "in", ["pending", "processing", "failed"])
      .limit(500)
      .get(),
    db.collection("schools").select("name").get(),
  ]);

  const schoolNames = new Map(
    schools.docs.map((doc) => [doc.id, String(doc.data().name ?? "")])
  );
  const markerByUser = new Map(
    markers.docs.flatMap((doc) => {
      const userId = safeDocumentId(doc.data().userId);
      return userId
        ? [[userId, doc] as const]
        : [];
    })
  );
  const userRefs = markers.docs.flatMap((marker) => {
    const data = marker.data();
    const schoolId = safeDocumentId(data.schoolId);
    const userId = safeDocumentId(data.userId);
    return schoolId && userId
      ? [db.doc(`schools/${schoolId}/users/${userId}`)]
      : [];
  });
  const studentRefs = jobs.docs.flatMap((job) => {
    const data = job.data();
    const schoolId = safeDocumentId(data.schoolId);
    const studentId = safeDocumentId(data.studentId);
    return data.kind === "student" && schoolId && studentId
      ? [db.doc(`schools/${schoolId}/students/${studentId}`)]
      : [];
  });
  const subjects =
    userRefs.length + studentRefs.length > 0
      ? await db.getAll(...userRefs, ...studentRefs)
      : [];
  const subjectNames = new Map(
    subjects.map((doc) => {
      const data = doc.data() ?? {};
      const name = `${data.firstName ?? ""} ${data.lastName ?? ""}`.trim();
      return [doc.ref.path, name] as const;
    })
  );

  const operations: DeletionOperation[] = [];
  const jobRequesterIds = new Set<string>();
  for (const job of jobs.docs) {
    const data = job.data();
    const requesterUid = safeDocumentId(data.requesterUid);
    if (requesterUid) jobRequesterIds.add(requesterUid);
    const marker = requesterUid ? markerByUser.get(requesterUid) : undefined;
    const schoolId =
      safeDocumentId(data.schoolId) ?? safeDocumentId(marker?.data().schoolId);
    const isStudent = data.kind === "student";
    const studentId = safeDocumentId(data.studentId);
    const subjectPath = isStudent && schoolId && studentId
      ? `schools/${schoolId}/students/${studentId}`
      : schoolId && requesterUid
        ? `schools/${schoolId}/users/${requesterUid}`
        : "";
    const attemptCount = Number.isFinite(Number(data.attemptCount))
      ? Number(data.attemptCount)
      : 0;
    const status: DeletionOperationStatus =
      data.status === "processing"
        ? "processing"
        : data.status === "failed" && attemptCount >= 5
          ? "manual-review"
          : data.status === "failed"
            ? "retrying"
            : "pending";

    operations.push({
      id: job.id,
      kind: isStudent ? "student" : "account",
      status,
      schoolId,
      schoolName: schoolId ? schoolNames.get(schoolId) : undefined,
      subjectName:
        subjectNames.get(subjectPath) ||
        (isStudent ? "Student account" : "User account"),
      scheduledAt:
        toISO(data.nextAttemptAt) ||
        toISO(data.scheduledDeletionAt) ||
        toISO(data.requestedAt),
      attemptCount,
      errorCode: safeErrorCode(data.errorCode),
      canCancel: false,
      canRetry: status === "manual-review",
    });
  }

  const now = Date.now();
  for (const marker of markers.docs) {
    const data = marker.data();
    const userId = safeDocumentId(data.userId) ?? safeDocumentId(marker.id);
    if (!userId) continue;
    if (jobRequesterIds.has(userId)) continue;
    const schoolId = safeDocumentId(data.schoolId);
    const scheduledAt = toISO(data.scheduledDeletionAt);
    const isCoolingOff = Boolean(scheduledAt) && Date.parse(scheduledAt) > now;
    const userPath = schoolId ? `schools/${schoolId}/users/${userId}` : "";
    operations.push({
      id: marker.id,
      kind: "staff-account",
      status: isCoolingOff ? "cooling-off" : "pending",
      schoolId,
      schoolName: schoolId ? schoolNames.get(schoolId) : undefined,
      subjectName: subjectNames.get(userPath) || "Staff account",
      scheduledAt,
      attemptCount: 0,
      canCancel: isCoolingOff,
      canRetry: false,
      userId,
    });
  }

  return operations.sort((a, b) => {
    const priority = (item: DeletionOperation) =>
      item.status === "manual-review" ? 0 : item.status === "retrying" ? 1 : 2;
    return priority(a) - priority(b) || a.scheduledAt.localeCompare(b.scheduledAt);
  });
}
