import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";

export type DeliveryIncidentKind = "onboarding" | "notification";
export type DeliveryIncidentSource =
  | "parentOnboarding"
  | "staffOnboarding"
  | "notification";

export interface DeliveryIncident {
  id: string;
  schoolId: string;
  schoolName: string;
  kind: DeliveryIncidentKind;
  source: DeliveryIncidentSource;
  status: "failed" | "partial";
  createdAt: string;
  recipientCount: number;
  sentCount: number;
  failedCount: number;
  skippedCount: number;
  errorSummary: string;
  attentionStatus: "open" | "resolved" | "retried";
  canRetry: boolean;
}

function toISO(value: unknown): string {
  if (value instanceof Date) return value.toISOString();
  if (
    value &&
    typeof value === "object" &&
    "toDate" in value &&
    typeof (value as { toDate?: unknown }).toDate === "function"
  ) {
    return (value as { toDate: () => Date }).toDate().toISOString();
  }
  return "";
}

// Provider errors can contain recipient addresses or transport internals. The
// command centre gets a small operator-safe category; raw details remain in
// protected server logs and the original Admin-SDK-only document.
function safeErrorSummary(raw: unknown): string {
  const value = typeof raw === "string" ? raw : "";
  const lower = value.toLowerCase();
  if (!value) return "Delivery did not complete.";
  if (lower.includes("demo tenant") || lower.includes("demo school")) {
    return "External delivery is disabled for the shared demo tenant.";
  }
  if (lower.includes("sendgrid api key")) {
    return "Email provider configuration is unavailable.";
  }
  if (lower.includes("no linked parents")) {
    return "No linked parents matched the selected audience.";
  }
  if (lower.includes("daily notification limit")) {
    return "The school reached its daily notification recipient limit.";
  }
  if (lower.includes("per-campaign limit")) {
    return "The selected audience exceeded the per-campaign recipient limit.";
  }
  if (lower.includes("push") && lower.includes("failed")) {
    return "One or more push notifications could not be delivered; in-app messages were retained.";
  }
  return "Delivery failed. Use the incident ID to correlate protected server logs.";
}

function attentionStatus(data: FirebaseFirestore.DocumentData) {
  return data.attentionStatus === "resolved" || data.attentionStatus === "retried"
    ? data.attentionStatus
    : "open";
}

function hasOnboardingRetryTargets(
  source: "parentOnboarding" | "staffOnboarding",
  data: FirebaseFirestore.DocumentData
): boolean {
  const isValidId = (id: unknown) =>
    typeof id === "string" &&
    id.length > 0 &&
    id.length <= 256 &&
    !id.includes("/");
  const recipients = Array.isArray(data.recipients) ? data.recipients : [];
  if (recipients.length > 0) {
    return recipients.some((recipient) => {
      const id =
        source === "parentOnboarding"
          ? recipient?.studentId
          : recipient?.userId;
      return recipient?.status === "failed" && isValidId(id);
    });
  }
  const targets =
    source === "parentOnboarding" ? data.targetStudentIds : data.targetUserIds;
  return Array.isArray(targets) && targets.some(isValidId);
}

function onboardingIncident(
  schoolId: string,
  schoolName: string,
  source: "parentOnboarding" | "staffOnboarding",
  doc: FirebaseFirestore.QueryDocumentSnapshot
): DeliveryIncident {
  const data = doc.data();
  const counts = data.deliveryCounts ?? {};
  return {
    id: doc.id,
    schoolId,
    schoolName,
    kind: "onboarding",
    source,
    status: data.status === "partial" ? "partial" : "failed",
    createdAt: toISO(data.createdAt),
    recipientCount: Number(data.recipientCount ?? 0),
    sentCount: Number(counts.sent ?? 0),
    failedCount: Number(counts.failed ?? 0),
    skippedCount: Number(counts.skipped ?? 0),
    errorSummary: safeErrorSummary(data.errorSummary),
    attentionStatus: attentionStatus(data),
    canRetry: hasOnboardingRetryTargets(source, data),
  };
}

function notificationIncident(
  schoolId: string,
  schoolName: string,
  doc: FirebaseFirestore.QueryDocumentSnapshot
): DeliveryIncident {
  const data = doc.data();
  const counts = data.deliveryCounts ?? {};
  return {
    id: doc.id,
    schoolId,
    schoolName,
    kind: "notification",
    source: "notification",
    status: data.status === "partial" ? "partial" : "failed",
    createdAt: toISO(data.createdAt),
    recipientCount: Number(data.recipientCounts?.parents ?? 0),
    sentCount: Number(counts.pushSent ?? 0),
    failedCount: Number(counts.pushFailed ?? 0),
    skippedCount: Number(counts.pushSkipped ?? 0),
    errorSummary: safeErrorSummary(data.errorSummary),
    attentionStatus: attentionStatus(data),
    // A replacement campaign can duplicate already-written inbox messages.
    canRetry: false,
  };
}

export async function listDeliveryIncidents(): Promise<DeliveryIncident[]> {
  const db = getAdminDb();
  const schools = await db.collection("schools").select("name").get();
  const incidents: DeliveryIncident[] = [];

  await Promise.all(
    schools.docs.map(async (school) => {
      const [parents, staff, notifications] = await Promise.all([
        school.ref
          .collection("parentOnboardingEmails")
          .where("status", "in", ["failed", "partial"])
          .get(),
        school.ref
          .collection("staffOnboardingEmails")
          .where("status", "in", ["failed", "partial"])
          .get(),
        school.ref
          .collection("notificationCampaigns")
          .where("status", "in", ["failed", "partial"])
          .get(),
      ]);
      const schoolName = String(school.data().name ?? school.id);
      incidents.push(
        ...parents.docs.map((doc) =>
          onboardingIncident(school.id, schoolName, "parentOnboarding", doc)
        ),
        ...staff.docs.map((doc) =>
          onboardingIncident(school.id, schoolName, "staffOnboarding", doc)
        ),
        ...notifications.docs.map((doc) =>
          notificationIncident(school.id, schoolName, doc)
        )
      );
    })
  );

  return incidents.sort((a, b) => b.createdAt.localeCompare(a.createdAt));
}
