import type { Firestore, WriteBatch } from "firebase-admin/firestore";
import { z } from "zod";
import { logAuditEvent, ServerOpsValidationError, type Actor } from "./audit";
import { assertSuperAdmin } from "./authority";

const OFFBOARD_SUBCOLLECTIONS = [
  "users",
  "students",
  "parents",
  "classes",
  "allocations",
  "books",
  "readingLogs",
] as const;

export type OffboardSubcollection = (typeof OFFBOARD_SUBCOLLECTIONS)[number];
export type OffboardStep = "school" | OffboardSubcollection;

const stepSchema = z.enum(["school", ...OFFBOARD_SUBCOLLECTIONS]);

// Firestore commits at most 500 writes per batch.
const FIRESTORE_BATCH_LIMIT = 500;

export interface OffboardPreview {
  schoolName: string;
  users: number;
  students: number;
  parents: number;
  classes: number;
  allocations: number;
  books: number;
  readingLogs: number;
}

// Read-only count of what an offboard would touch. Returns null if the school
// does not exist.
export async function getOffboardPreview(
  db: Firestore,
  schoolId: string
): Promise<OffboardPreview | null> {
  if (!schoolId || typeof schoolId !== "string") {
    throw new ServerOpsValidationError("schoolId is required");
  }

  const schoolDoc = await db.collection("schools").doc(schoolId).get();
  if (!schoolDoc.exists) return null;

  const schoolName = (schoolDoc.data()?.name as string) ?? schoolId;
  const counts = await Promise.all(
    OFFBOARD_SUBCOLLECTIONS.map(async (col) => {
      const snap = await db
        .collection("schools").doc(schoolId)
        .collection(col).count().get();
      return snap.data().count;
    })
  );

  return {
    schoolName,
    users: counts[0],
    students: counts[1],
    parents: counts[2],
    classes: counts[3],
    allocations: counts[4],
    books: counts[5],
    readingLogs: counts[6],
  };
}

export interface OffboardSchoolStepParams {
  schoolId: string;
  step: OffboardStep;
}

export interface OffboardSchoolStepResult {
  success: true;
  step: OffboardStep;
  affected: number;
}

// Executes one offboard step — either the school doc itself or one named
// subcollection — soft-deactivating every doc (isActive: false). Step-wise by
// design so the admin UI can drive a progress bar and a failure only loses one
// step's worth of work.
export async function offboardSchoolStep(
  db: Firestore,
  actor: Actor,
  params: OffboardSchoolStepParams
): Promise<OffboardSchoolStepResult> {
  await assertSuperAdmin(db, actor.uid);
  const { schoolId } = params;
  if (!schoolId || typeof schoolId !== "string") {
    throw new ServerOpsValidationError("schoolId is required");
  }

  const stepParsed = stepSchema.safeParse(params.step);
  if (!stepParsed.success) {
    throw new ServerOpsValidationError(
      `step must be one of: school, ${OFFBOARD_SUBCOLLECTIONS.join(", ")}`
    );
  }
  const step = stepParsed.data;

  let affected = 0;

  if (step === "school") {
    const schoolRef = db.collection("schools").doc(schoolId);
    const schoolDoc = await schoolRef.get();
    // Guard against double-execution.
    if (schoolDoc.exists && schoolDoc.data()?.isActive === false) {
      throw new ServerOpsValidationError("School is already deactivated");
    }
    // Set the materialised `access` map alongside the legacy `isActive` flag so
    // off-boarding actually cuts access: the security rules and app gate on
    // `access`, not `isActive`. academicYear is best-effort from config.
    const cfg = await db.collection("config").doc("academicYear").get();
    const academicYear =
      (cfg.data()?.currentAcademicYear as number | undefined) ?? 0;
    await schoolRef.update({
      isActive: false,
      access: {
        status: "suspended",
        academicYear,
        reason: "offboarded",
        updatedAt: new Date(),
      },
    });
    affected = 1;
  } else {
    const snapshot = await db
      .collection("schools").doc(schoolId)
      .collection(step).get();

    if (!snapshot.empty) {
      // The students step additionally zeroes the materialised access verdict
      // so a parent's reading-log create is denied immediately (the rules gate
      // on access.status / access.expiresAt, not isActive).
      const deactivate =
        step === "students"
          ? { isActive: false, "access.status": "suspended" }
          : { isActive: false };

      const batches: WriteBatch[] = [];
      let currentBatch = db.batch();
      let operationCount = 0;

      for (const doc of snapshot.docs) {
        currentBatch.update(doc.ref, deactivate);
        operationCount += 1;
        if (operationCount % FIRESTORE_BATCH_LIMIT === 0) {
          batches.push(currentBatch);
          currentBatch = db.batch();
        }
      }
      if (operationCount % FIRESTORE_BATCH_LIMIT !== 0) {
        batches.push(currentBatch);
      }

      await Promise.all(batches.map((b) => b.commit()));
    }
    affected = snapshot.size;
  }

  await logAuditEvent(db, {
    action: "offboard.deactivate",
    performedBy: actor.uid,
    performedByEmail: actor.email,
    targetType: "school",
    targetId: schoolId,
    schoolId,
    after: { step, affected },
  }).catch((e) => {
    console.error("[server-ops] audit log failed for offboard.deactivate", e);
  });

  return { success: true, step, affected };
}
