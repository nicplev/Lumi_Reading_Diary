import { NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import { verifySession } from "@/lib/auth";
import { getAdminDb } from "@/lib/firebase-admin";
import { logAuditEvent } from "@/lib/firestore/audit-log";

const schema = z.object({
  schoolId: z.string().min(1).max(256).refine((value) => !value.includes("/")),
  recordId: z.string().min(1).max(256).refine((value) => !value.includes("/")),
  source: z.enum(["parentOnboarding", "staffOnboarding", "notification"]),
  action: z.enum(["retry", "acknowledge"]),
});

const collections = {
  parentOnboarding: "parentOnboardingEmails",
  staffOnboarding: "staffOnboardingEmails",
  notification: "notificationCampaigns",
} as const;

function failedTargetIds(
  source: "parentOnboarding" | "staffOnboarding",
  data: FirebaseFirestore.DocumentData
): string[] {
  const isValidTargetId = (id: unknown): id is string =>
    typeof id === "string" &&
    id.length > 0 &&
    id.length <= 256 &&
    !id.includes("/");
  const recipients = Array.isArray(data.recipients) ? data.recipients : [];
  const failed = recipients
    .filter((recipient) => recipient?.status === "failed")
    .map((recipient) =>
      source === "parentOnboarding" ? recipient.studentId : recipient.userId
    )
    .filter(isValidTargetId);
  if (failed.length > 0) return [...new Set(failed)];

  // A processed batch with recipient results but no failed recipient IDs is
  // not safe to replay: falling back to the original targets could resend to
  // people who already received the email. The original targets are only a
  // safe fallback for a preflight failure with no recipient results at all.
  if (recipients.length > 0) return [];

  const fallback =
    source === "parentOnboarding" ? data.targetStudentIds : data.targetUserIds;
  return Array.isArray(fallback)
    ? [...new Set(fallback.filter(isValidTargetId))]
    : [];
}

export async function POST(request: Request) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const input = schema.parse(await request.json());
    if (input.action === "retry" && input.source === "notification") {
      return NextResponse.json(
        { error: "Notification campaigns cannot be retried safely because inbox messages may already exist." },
        { status: 409 }
      );
    }

    const db = getAdminDb();
    const collection = collections[input.source];
    const originalRef = db.doc(
      `schools/${input.schoolId}/${collection}/${input.recordId}`
    );
    let retryJobId: string | undefined;

    await db.runTransaction(async (transaction) => {
      const original = await transaction.get(originalRef);
      if (!original.exists) throw new Error("not-found");
      const data = original.data()!;
      if (data.status !== "failed" && data.status !== "partial") {
        throw new Error("not-actionable");
      }

      if (data.attentionStatus === "retried") {
        if (
          input.action === "retry" &&
          typeof data.retryJobId === "string" &&
          data.retryJobId.length > 0
        ) {
          retryJobId = data.retryJobId;
          return;
        }
        throw new Error("not-actionable");
      }
      if (data.attentionStatus === "resolved") {
        throw new Error("not-actionable");
      }

      if (input.action === "acknowledge") {
        transaction.update(originalRef, {
          attentionStatus: "resolved",
          attentionResolvedAt: FieldValue.serverTimestamp(),
          attentionResolvedBy: session.uid,
        });
        return;
      }

      if (typeof data.retryJobId === "string" && data.retryJobId.length > 0) {
        retryJobId = data.retryJobId;
        return;
      }

      const source = input.source as "parentOnboarding" | "staffOnboarding";
      const targetIds = failedTargetIds(source, data);
      if (targetIds.length === 0) throw new Error("no-targets");

      const retryRef = originalRef.parent.doc();
      retryJobId = retryRef.id;
      const retryData: Record<string, unknown> = {
        status: "queued",
        schoolId: input.schoolId,
        createdAt: FieldValue.serverTimestamp(),
        createdBy: session.uid,
        emailSubject:
          typeof data.emailSubject === "string"
            ? data.emailSubject.slice(0, 300)
            : null,
        customMessage:
          typeof data.customMessage === "string"
            ? data.customMessage.slice(0, 5_000)
            : null,
        retryOf: input.recordId,
      };
      if (source === "parentOnboarding") {
        retryData.targetStudentIds = targetIds;
        retryData.generateMissingCodes = data.generateMissingCodes !== false;
      } else {
        retryData.targetUserIds = targetIds;
      }

      transaction.set(retryRef, retryData);
      transaction.update(originalRef, {
        attentionStatus: "retried",
        attentionResolvedAt: FieldValue.serverTimestamp(),
        attentionResolvedBy: session.uid,
        retryJobId: retryRef.id,
      });
    });

    await logAuditEvent({
      action: `deliveryIncident.${input.action}`,
      performedBy: session.uid,
      performedByEmail: session.email,
      targetType: "deliveryIncident",
      targetId: input.recordId,
      schoolId: input.schoolId,
      metadata: {
        source: input.source,
        ...(retryJobId ? { retryJobId } : {}),
      },
    });

    return NextResponse.json({ success: true, retryJobId });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: "Invalid request", details: error.issues }, { status: 400 });
    }
    const code = error instanceof Error ? error.message : "";
    if (code === "not-found") {
      return NextResponse.json({ error: "Incident not found" }, { status: 404 });
    }
    if (code === "not-actionable") {
      return NextResponse.json({ error: "Incident is no longer actionable" }, { status: 409 });
    }
    if (code === "no-targets") {
      return NextResponse.json({ error: "No failed recipients are available to retry" }, { status: 409 });
    }
    console.error("Delivery incident action failed", error);
    return NextResponse.json({ error: "Delivery incident action failed" }, { status: 500 });
  }
}
