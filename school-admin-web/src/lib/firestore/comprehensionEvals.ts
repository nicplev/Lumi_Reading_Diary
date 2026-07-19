// AI comprehension evaluations — server-only Admin SDK queries.
//
// NOTE: school-admin-web is intentionally outside the pnpm workspace and
// cannot use @lumi/server-ops; logic is mirrored manually (see
// comprehensionAudio.ts). Reads are Admin SDK, so the class scoping below
// is the authorisation — mirror the app's rules: teachers only see classes
// they teach; schoolAdmin sees the whole school.
//
// The numeric sortKey is DELIBERATELY never selected or returned: levels +
// confidence only, in the UI and in CSV exports.

import { adminDb } from "@/lib/firebase/admin";

export interface ComprehensionEvalRecord {
  logId: string;
  studentId: string;
  classId: string;
  logDate: string | null;
  status: string;
  overallLevel: string | null;
  confidence: string | null;
  summary: string | null;
  flags: string[];
  assessable: boolean;
  questionTextUsed: string | null;
  questionSource: string | null;
  transcript: string | null;
  transcriptRemovedAt: string | null;
  criterionScores: Array<{
    criterionId: string;
    score: number;
    evidence: string;
  }>;
  audioUploadedAt: string | null;
  evaluatedAt: string | null;
}

function toISO(value: unknown): string | null {
  if (!value || typeof value !== "object") return null;
  const anyValue = value as { toDate?: () => Date };
  return typeof anyValue.toDate === "function"
    ? anyValue.toDate().toISOString()
    : null;
}

function toRecord(
  id: string,
  data: FirebaseFirestore.DocumentData
): ComprehensionEvalRecord {
  return {
    logId: id,
    studentId: typeof data.studentId === "string" ? data.studentId : "",
    classId: typeof data.classId === "string" ? data.classId : "",
    logDate: toISO(data.logDate),
    status: typeof data.status === "string" ? data.status : "failed",
    overallLevel:
      typeof data.overallLevel === "string" ? data.overallLevel : null,
    confidence: typeof data.confidence === "string" ? data.confidence : null,
    summary: typeof data.summary === "string" ? data.summary : null,
    flags: Array.isArray(data.flags)
      ? data.flags.filter((f): f is string => typeof f === "string")
      : [],
    assessable: data.assessable === true,
    questionTextUsed:
      typeof data.questionTextUsed === "string" ? data.questionTextUsed : null,
    questionSource:
      typeof data.questionSource === "string" ? data.questionSource : null,
    transcript: typeof data.transcript === "string" ? data.transcript : null,
    transcriptRemovedAt: toISO(data.transcriptRemovedAt),
    criterionScores: Array.isArray(data.criterionScores)
      ? data.criterionScores
          .filter((c): c is Record<string, unknown> => !!c && typeof c === "object")
          .map((c) => ({
            criterionId: typeof c.criterionId === "string" ? c.criterionId : "",
            score: typeof c.score === "number" ? c.score : 0,
            evidence: typeof c.evidence === "string" ? c.evidence : "",
          }))
      : [],
    audioUploadedAt: toISO(data.audioUploadedAt),
    evaluatedAt: toISO(data.evaluatedAt),
  };
}

// Fail-closed feature gate: platform flag + school entitlement.
export async function aiEvaluationEnabledForSchool(
  schoolId: string
): Promise<boolean> {
  const [flagSnap, schoolSnap] = await Promise.all([
    adminDb.doc("platformConfig/aiEvaluation").get(),
    adminDb.doc(`schools/${schoolId}`).get(),
  ]);
  if (flagSnap.data()?.enabled !== true) return false;
  const settings = (schoolSnap.data()?.settings ?? {}) as Record<
    string,
    unknown
  >;
  const ai = settings.aiEvaluation as Record<string, unknown> | undefined;
  return ai?.enabled === true;
}

// Teacher scoping mirror of the app rules: a teacher may read a class's
// evals only when they teach that class; schoolAdmin reads any class.
export async function teacherTeachesClass(
  schoolId: string,
  classId: string,
  uid: string
): Promise<boolean> {
  const classSnap = await adminDb
    .doc(`schools/${schoolId}/classes/${classId}`)
    .get();
  const teacherIds = classSnap.data()?.teacherIds;
  return Array.isArray(teacherIds) && teacherIds.includes(uid);
}

export async function listClassEvals(
  schoolId: string,
  classId: string,
  limit = 300
): Promise<ComprehensionEvalRecord[]> {
  const snap = await adminDb
    .collection(`schools/${schoolId}/comprehensionEvals`)
    .where("classId", "==", classId)
    .orderBy("evaluatedAt", "desc")
    .limit(limit)
    .get();
  return snap.docs.map((doc) => toRecord(doc.id, doc.data()));
}

export async function listStudentEvals(
  schoolId: string,
  classId: string,
  studentId: string,
  limit = 50
): Promise<ComprehensionEvalRecord[]> {
  const snap = await adminDb
    .collection(`schools/${schoolId}/comprehensionEvals`)
    .where("classId", "==", classId)
    .where("studentId", "==", studentId)
    .orderBy("logDate", "desc")
    .limit(limit)
    .get();
  return snap.docs.map((doc) => toRecord(doc.id, doc.data()));
}
