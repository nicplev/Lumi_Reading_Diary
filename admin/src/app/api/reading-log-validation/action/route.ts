import { NextResponse } from "next/server";
import { deleteOneComprehensionAudio } from "@lumi/server-ops";
import { FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import { verifySession } from "@/lib/auth";
import { getAdminDb, getAdminStorage } from "@/lib/firebase-admin";
import { logAuditEvent } from "@/lib/firestore/audit-log";
import { validateReadingLogForReview } from "@/lib/reading-log-validation";

const documentId = z
  .string()
  .min(1)
  .max(256)
  .refine((value) => !value.includes("/"));

const schema = z.object({
  schoolId: documentId,
  logId: documentId,
  action: z.enum(["revalidate", "acknowledge", "delete"]),
});

class ActionError extends Error {
  constructor(
    public readonly code: "not-found" | "not-actionable" | "invalid-student-id"
  ) {
    super(code);
  }
}

export async function POST(request: Request) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const input = schema.parse(await request.json());
    const db = getAdminDb();
    const logRef = db.doc(
      `schools/${input.schoolId}/readingLogs/${input.logId}`
    );
    const logSnapshot = await logRef.get();
    if (!logSnapshot.exists) throw new ActionError("not-found");
    const log = logSnapshot.data() ?? {};
    if (log.validationStatus !== "invalid") {
      throw new ActionError("not-actionable");
    }

    if (input.action === "acknowledge") {
      await logRef.update({
        validationReviewStatus: "acknowledged",
        validationReviewedAt: FieldValue.serverTimestamp(),
        validationReviewedBy: session.uid,
      });
      await writeAudit(input, session, { outcome: "leftExcluded" });
      return NextResponse.json({ success: true });
    }

    if (input.action === "delete") {
      if (log.comprehensionAudioUploaded === true) {
        await deleteOneComprehensionAudio(db, getAdminStorage(), {
          schoolId: input.schoolId,
          logId: input.logId,
          actor: { uid: session.uid, email: session.email },
          source: "manualSuperAdmin",
        });
      }

      await Promise.all([
        db.recursiveDelete(logRef),
        db.doc(
          `schools/${input.schoolId}/comprehensionEvals/${input.logId}`
        ).delete(),
        db.doc(`aiEvalJobs/${input.schoolId}_${input.logId}`).delete(),
      ]);
      await writeAudit(input, session, { outcome: "deleted" });
      return NextResponse.json({ success: true });
    }

    const studentId = log.studentId;
    if (
      typeof studentId !== "string" ||
      studentId.length === 0 ||
      studentId.includes("/")
    ) {
      throw new ActionError("invalid-student-id");
    }
    const studentSnapshot = await db
      .doc(`schools/${input.schoolId}/students/${studentId}`)
      .get();
    const errors = validateReadingLogForReview(log, {
      exists: studentSnapshot.exists,
      parentIds: studentSnapshot.data()?.parentIds,
    });

    if (errors.length === 0) {
      await logRef.update({
        validationStatus: FieldValue.delete(),
        validationErrors: FieldValue.delete(),
        validationReviewStatus: FieldValue.delete(),
        validationReviewedAt: FieldValue.delete(),
        validationReviewedBy: FieldValue.delete(),
        validationRevalidatedAt: FieldValue.serverTimestamp(),
        validationRevalidatedBy: session.uid,
      });
    } else {
      await logRef.update({
        validationStatus: "invalid",
        validationErrors: errors,
        validationReviewStatus: "open",
        validationReviewedAt: FieldValue.delete(),
        validationReviewedBy: FieldValue.delete(),
        validationRevalidatedAt: FieldValue.serverTimestamp(),
        validationRevalidatedBy: session.uid,
      });
    }

    await writeAudit(input, session, {
      outcome: errors.length === 0 ? "restored" : "leftExcluded",
      validationErrorCount: errors.length,
    });
    return NextResponse.json({
      success: true,
      valid: errors.length === 0,
      validationErrors: errors,
    });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: "Invalid request" }, { status: 400 });
    }
    if (error instanceof ActionError) {
      if (error.code === "not-found") {
        return NextResponse.json({ error: "Reading log not found" }, { status: 404 });
      }
      if (error.code === "invalid-student-id") {
        return NextResponse.json(
          { error: "The log has an invalid student reference and cannot be revalidated" },
          { status: 409 }
        );
      }
      return NextResponse.json(
        { error: "Reading log is no longer marked invalid" },
        { status: 409 }
      );
    }
    console.error("Reading-log validation action failed", error);
    return NextResponse.json(
      { error: "Reading-log validation action failed" },
      { status: 500 }
    );
  }
}

async function writeAudit(
  input: z.infer<typeof schema>,
  session: NonNullable<Awaited<ReturnType<typeof verifySession>>>,
  metadata: Record<string, unknown>
) {
  await logAuditEvent({
    action: `readingLogValidation.${input.action}`,
    performedBy: session.uid,
    performedByEmail: session.email,
    targetType: "readingLog",
    targetId: input.logId,
    schoolId: input.schoolId,
    metadata,
  }).catch((error) =>
    console.error("Reading-log validation audit write failed", error)
  );
}
