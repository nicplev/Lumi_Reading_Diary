import type { Firestore } from "firebase-admin/firestore";
import { FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import { logAuditEvent, ServerOpsValidationError, type Actor } from "./audit";

const paramsSchema = z.object({
  schoolId: z.string().min(1, "schoolId is required"),
  studentId: z.string().min(1, "studentId is required"),
  level: z.string().min(1, "Reading level is required"),
  levelIndex: z.number().optional(),
  reason: z.string().optional(),
  source: z.string().optional(),
  changedByName: z.string().min(1).optional(),
});

export interface UpdateStudentReadingLevelParams {
  schoolId: string;
  studentId: string;
  level: string;
  levelIndex?: number;
  reason?: string;
  source?: string;
  // Display name to record on the readingLevelEvents row. Falls back to "Admin"
  // if the caller doesn't supply one (e.g. ID token without a name claim).
  changedByName?: string;
}

export interface UpdateStudentReadingLevelResult {
  success: true;
}

// Two writes per call: the student doc gets the new level + tracking fields,
// and a per-student readingLevelEvents subcollection row captures the
// before/after for history. These are NOT batched on purpose — the events
// collection backs analytics queries that should reflect the level transition
// even if the parent update partially fails. The aggregateStudentStats
// firestore trigger in functions/ fires on either write.
export async function updateStudentReadingLevel(
  db: Firestore,
  actor: Actor,
  params: UpdateStudentReadingLevelParams
): Promise<UpdateStudentReadingLevelResult> {
  const parsed = paramsSchema.safeParse(params);
  if (!parsed.success) {
    throw new ServerOpsValidationError(
      parsed.error.issues.map((e) => e.message).join(", ")
    );
  }
  const { schoolId, studentId, level, levelIndex, reason, source, changedByName } = parsed.data;

  const studentRef = db
    .collection("schools").doc(schoolId)
    .collection("students").doc(studentId);
  const studentDoc = await studentRef.get();
  if (!studentDoc.exists) {
    throw new ServerOpsValidationError("Student not found");
  }
  const studentData = studentDoc.data()!;

  await studentRef.update({
    currentReadingLevel: level,
    currentReadingLevelIndex: levelIndex ?? null,
    readingLevelUpdatedAt: FieldValue.serverTimestamp(),
    readingLevelUpdatedBy: actor.uid,
    readingLevelSource: source ?? "admin",
  });

  await studentRef.collection("readingLevelEvents").add({
    studentId,
    schoolId,
    classId: studentData.classId,
    fromLevel: studentData.currentReadingLevel || null,
    toLevel: level,
    fromLevelIndex: studentData.currentReadingLevelIndex ?? null,
    toLevelIndex: levelIndex ?? null,
    reason: reason || null,
    source: source ?? "admin",
    changedByUserId: actor.uid,
    changedByRole: "admin",
    changedByName: changedByName ?? "Admin",
    createdAt: FieldValue.serverTimestamp(),
  });

  await logAuditEvent(db, {
    action: "student.updateLevel",
    performedBy: actor.uid,
    performedByEmail: actor.email,
    targetType: "student",
    targetId: studentId,
    schoolId,
    after: { level, levelIndex, reason, source },
  }).catch((e) => {
    console.error("[server-ops] audit log failed for student.updateLevel", e);
  });

  return { success: true };
}
