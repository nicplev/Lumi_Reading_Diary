import type { Firestore } from "firebase-admin/firestore";
import { z } from "zod";
import { logAuditEvent, ServerOpsValidationError, type Actor } from "./audit";

export const bulkStudentRowSchema = z.object({
  firstName: z.string().min(1, "First name is required").max(100, "First name too long"),
  lastName: z.string().min(1, "Last name is required").max(100, "Last name too long"),
  studentId: z.string().max(50, "Student ID too long").optional(),
  className: z.string().min(1, "Class name is required").max(100, "Class name too long"),
  currentReadingLevel: z.string().max(50, "Reading level too long").optional(),
});

export const MAX_BULK_ROWS = 1000;

export type BulkStudentRow = z.infer<typeof bulkStudentRowSchema>;

export interface BulkImportStudentsParams {
  schoolId: string;
  students: unknown[];
}

export interface BulkImportStudentsResult {
  created: number;
  errors: { row: number; message: string }[];
}

// Firestore commits at most 500 writes per batch.
const FIRESTORE_BATCH_LIMIT = 500;

export async function bulkImportStudents(
  db: Firestore,
  actor: Actor,
  params: BulkImportStudentsParams
): Promise<BulkImportStudentsResult> {
  const { schoolId, students } = params;

  if (!schoolId || typeof schoolId !== "string") {
    throw new ServerOpsValidationError("schoolId is required");
  }
  if (!Array.isArray(students)) {
    throw new ServerOpsValidationError("students must be an array");
  }
  if (students.length === 0) {
    throw new ServerOpsValidationError("No students to import");
  }
  if (students.length > MAX_BULK_ROWS) {
    throw new ServerOpsValidationError(`Maximum ${MAX_BULK_ROWS} rows per import`);
  }

  const classesSnap = await db
    .collection("schools").doc(schoolId)
    .collection("classes").get();
  const classNameMap = new Map<string, string>();
  for (const doc of classesSnap.docs) {
    const name = doc.data().name;
    if (typeof name === "string") {
      classNameMap.set(name.toLowerCase(), doc.id);
    }
  }

  const studentsCol = db
    .collection("schools").doc(schoolId)
    .collection("students");

  const errors: { row: number; message: string }[] = [];
  let created = 0;
  let batch = db.batch();
  let batchCount = 0;

  for (let i = 0; i < students.length; i++) {
    const result = bulkStudentRowSchema.safeParse(students[i]);
    if (!result.success) {
      errors.push({
        row: i + 1,
        message: result.error.issues.map((e) => e.message).join(", "),
      });
      continue;
    }

    const classId = classNameMap.get(result.data.className.toLowerCase());
    if (!classId) {
      errors.push({
        row: i + 1,
        message: `Class "${result.data.className}" not found`,
      });
      continue;
    }

    const docRef = studentsCol.doc();
    batch.set(docRef, {
      firstName: result.data.firstName,
      lastName: result.data.lastName,
      studentId: result.data.studentId || null,
      classId,
      currentReadingLevel: result.data.currentReadingLevel || null,
      parentIds: [],
      levelHistory: [],
      isActive: true,
      createdAt: new Date(),
    });

    created += 1;
    batchCount += 1;

    if (batchCount === FIRESTORE_BATCH_LIMIT) {
      await batch.commit();
      batch = db.batch();
      batchCount = 0;
    }
  }

  if (batchCount > 0) {
    await batch.commit();
  }

  await logAuditEvent(db, {
    action: "student.bulkImport",
    performedBy: actor.uid,
    performedByEmail: actor.email,
    targetType: "student",
    targetId: schoolId,
    schoolId,
    after: { created, errors: errors.length, totalRows: students.length },
  }).catch((e) => {
    console.error("[server-ops] audit log failed for student.bulkImport", e);
  });

  return { created, errors };
}
