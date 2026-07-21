import { createHash } from "node:crypto";
import { NextResponse } from "next/server";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { z } from "zod";
import { verifySession } from "@/lib/auth";
import { getAdminDb } from "@/lib/firebase-admin";
import { logAuditEvent } from "@/lib/firestore/audit-log";

const documentId = z
  .string()
  .min(1)
  .max(256)
  .refine((value) => !value.includes("/"));

const schema = z.discriminatedUnion("action", [
  z.object({ userId: documentId, action: z.literal("cancel") }),
  z.object({ jobId: documentId, action: z.literal("retry") }),
]);

function accountDeletionJobId(uid: string): string {
  return `account_${createHash("sha256").update(uid).digest("hex")}`;
}

export async function POST(request: Request) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const input = schema.parse(await request.json());
    const db = getAdminDb();
    if (input.action === "retry") {
      const jobRef = db.collection("deletionJobs").doc(input.jobId);
      await db.runTransaction(async (transaction) => {
        const job = await transaction.get(jobRef);
        if (!job.exists) throw new Error("not-found");
        const data = job.data() ?? {};
        if (data.status === "pending" && data.manualRetryRequestedAt) return;
        if (data.status !== "failed" || Number(data.attemptCount ?? 0) < 5) {
          throw new Error("not-actionable");
        }
        transaction.update(jobRef, {
          status: "pending",
          attemptCount: 0,
          scheduledDeletionAt: Timestamp.now(),
          nextAttemptAt: FieldValue.delete(),
          errorCode: FieldValue.delete(),
          expiresAt: FieldValue.delete(),
          leaseExpiresAt: FieldValue.delete(),
          manualRetryRequestedAt: FieldValue.serverTimestamp(),
          manualRetryRequestedBy: session.uid,
        });
      });
      await logAuditEvent({
        action: "deletionOperation.retry",
        performedBy: session.uid,
        performedByEmail: session.email,
        targetType: "deletionJob",
        targetId: input.jobId,
        metadata: { resetAfterMaxAttempts: true },
      }).catch((error) =>
        console.error("Deletion retry audit write failed", error)
      );
      return NextResponse.json({ success: true });
    }

    const markerRef = db.collection("pendingUserDeletions").doc(input.userId);
    const jobRef = db
      .collection("deletionJobs")
      .doc(accountDeletionJobId(input.userId));
    let schoolId = "";

    await db.runTransaction(async (transaction) => {
      const marker = await transaction.get(markerRef);
      if (!marker.exists) throw new Error("not-found");
      const markerData = marker.data() ?? {};
      schoolId = markerData.schoolId;
      if (
        typeof schoolId !== "string" ||
        schoolId.length === 0 ||
        schoolId.includes("/") ||
        markerData.userId !== input.userId
      ) {
        throw new Error("invalid-marker");
      }
      const scheduledDeletionAt = markerData.scheduledDeletionAt;
      if (
        !(scheduledDeletionAt instanceof Timestamp) ||
        scheduledDeletionAt.toMillis() <= Date.now()
      ) {
        throw new Error("cooling-off-ended");
      }

      const userRef = db.doc(`schools/${schoolId}/users/${input.userId}`);
      const [user, job] = await Promise.all([
        transaction.get(userRef),
        transaction.get(jobRef),
      ]);
      if (job.exists && job.data()?.status !== "completed") {
        throw new Error("job-started");
      }
      if (!user.exists) throw new Error("user-not-found");

      transaction.update(userRef, {
        pendingDeletion: FieldValue.delete(),
        scheduledDeletionAt: FieldValue.delete(),
      });
      transaction.delete(markerRef);
    });

    await logAuditEvent({
      action: "deletionOperation.cancel",
      performedBy: session.uid,
      performedByEmail: session.email,
      targetType: "user",
      targetId: input.userId,
      schoolId,
      metadata: { cancelledDuringCoolingOff: true },
    }).catch((error) =>
      console.error("Deletion cancellation audit write failed", error)
    );
    return NextResponse.json({ success: true });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: "Invalid request" }, { status: 400 });
    }
    const code = error instanceof Error ? error.message : "";
    if (code === "not-found" || code === "user-not-found") {
      return NextResponse.json(
        { error: "Scheduled deletion was not found" },
        { status: 404 }
      );
    }
    if (code === "cooling-off-ended" || code === "job-started") {
      return NextResponse.json(
        { error: "The cooling-off period has ended and deletion can no longer be cancelled" },
        { status: 409 }
      );
    }
    if (code === "not-actionable") {
      return NextResponse.json(
        { error: "Deletion job is no longer awaiting manual retry" },
        { status: 409 }
      );
    }
    if (code === "invalid-marker") {
      return NextResponse.json(
        { error: "The deletion record is invalid and requires manual review" },
        { status: 409 }
      );
    }
    console.error("Deletion operation failed", error);
    return NextResponse.json({ error: "Deletion operation failed" }, { status: 500 });
  }
}
