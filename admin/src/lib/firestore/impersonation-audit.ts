import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { toCsvString } from "@/lib/utils/export";

// Read layer for the developer-impersonation audit trail written by the
// Cloud Functions in the main monorepo. Two top-level collections:
//
//   /devImpersonationSessions/{sessionId}
//   /devImpersonationAudit/{eventId}
//
// Clients are locked out at the Firestore rule level; only the Admin SDK
// inside this server bundle (or the Cloud Functions) may read them.

function toISO(ts: unknown): string {
  if (!ts || typeof ts !== "object") return "";
  if (
    "toDate" in ts &&
    typeof (ts as { toDate: unknown }).toDate === "function"
  ) {
    return (ts as { toDate: () => Date }).toDate().toISOString();
  }
  return "";
}

function toMillis(ts: unknown): number | null {
  if (!ts || typeof ts !== "object") return null;
  if (
    "toMillis" in ts &&
    typeof (ts as { toMillis: unknown }).toMillis === "function"
  ) {
    return (ts as { toMillis: () => number }).toMillis();
  }
  return null;
}

export type ImpersonationStatus =
  | "active"
  | "ended"
  | "expired"
  | "revoked";

export type ImpersonationEventType =
  | "session_started"
  | "session_ended"
  | "session_expired"
  | "session_revoked"
  | "screen_viewed"
  | "export_requested"
  | "write_blocked_client"
  | "audit_exported";

export interface ImpersonationSession {
  id: string;
  devUid: string;
  devEmail: string;
  targetSchoolId: string;
  targetSchoolName?: string | null;
  targetUserId: string;
  targetUserEmail?: string | null;
  targetRole: string;
  reason: string;
  status: ImpersonationStatus;
  startedAt: string;
  expiresAt: string;
  endedAt: string | null;
  endReason: string | null;
  clientInfo?: Record<string, unknown>;
  /** ms remaining when status === 'active'; otherwise null. */
  remainingMs: number | null;
}

export interface ImpersonationAuditEvent {
  id: string;
  sessionId: string;
  devUid: string;
  devEmail: string;
  targetSchoolId: string;
  targetUserId: string;
  eventType: ImpersonationEventType;
  timestamp: string;
  details: Record<string, unknown>;
}

function sessionFromDoc(
  doc: FirebaseFirestore.QueryDocumentSnapshot | FirebaseFirestore.DocumentSnapshot
): ImpersonationSession {
  const data = doc.data() ?? {};
  const expiresMs = toMillis(data.expiresAt);
  const status = (data.status as ImpersonationStatus) ?? "ended";
  const remainingMs =
    status === "active" && expiresMs
      ? Math.max(0, expiresMs - Date.now())
      : null;
  return {
    id: doc.id,
    devUid: String(data.devUid ?? ""),
    devEmail: String(data.devEmail ?? ""),
    targetSchoolId: String(data.targetSchoolId ?? ""),
    targetSchoolName: (data.targetSchoolName as string | null | undefined) ?? null,
    targetUserId: String(data.targetUserId ?? ""),
    targetUserEmail: (data.targetUserEmail as string | null | undefined) ?? null,
    targetRole: String(data.targetRole ?? ""),
    reason: String(data.reason ?? ""),
    status,
    startedAt: toISO(data.startedAt),
    expiresAt: toISO(data.expiresAt),
    endedAt: toISO(data.endedAt) || null,
    endReason: (data.endReason as string | null | undefined) ?? null,
    clientInfo: (data.clientInfo as Record<string, unknown> | undefined) ?? {},
    remainingMs,
  };
}

function eventFromDoc(
  doc: FirebaseFirestore.QueryDocumentSnapshot | FirebaseFirestore.DocumentSnapshot
): ImpersonationAuditEvent {
  const data = doc.data() ?? {};
  return {
    id: doc.id,
    sessionId: String(data.sessionId ?? ""),
    devUid: String(data.devUid ?? ""),
    devEmail: String(data.devEmail ?? ""),
    targetSchoolId: String(data.targetSchoolId ?? ""),
    targetUserId: String(data.targetUserId ?? ""),
    eventType: (data.eventType as ImpersonationEventType) ?? "session_started",
    timestamp: toISO(data.timestamp),
    details: (data.details as Record<string, unknown> | undefined) ?? {},
  };
}

export async function listSessions(options?: {
  devUid?: string;
  devEmail?: string;
  targetSchoolId?: string;
  status?: ImpersonationStatus;
  startDate?: string;
  endDate?: string;
  limit?: number;
}): Promise<ImpersonationSession[]> {
  let query: FirebaseFirestore.Query = getAdminDb()
    .collection("devImpersonationSessions")
    .orderBy("startedAt", "desc");

  if (options?.devUid) {
    query = query.where("devUid", "==", options.devUid);
  }
  if (options?.devEmail) {
    query = query.where("devEmail", "==", options.devEmail.toLowerCase());
  }
  if (options?.targetSchoolId) {
    query = query.where("targetSchoolId", "==", options.targetSchoolId);
  }
  if (options?.status) {
    query = query.where("status", "==", options.status);
  }
  if (options?.startDate) {
    const d = new Date(options.startDate);
    if (!isNaN(d.getTime())) {
      query = query.where("startedAt", ">=", Timestamp.fromDate(d));
    }
  }
  if (options?.endDate) {
    const d = new Date(options.endDate);
    if (!isNaN(d.getTime())) {
      d.setHours(23, 59, 59, 999);
      query = query.where("startedAt", "<=", Timestamp.fromDate(d));
    }
  }

  query = query.limit(options?.limit ?? 200);
  const snap = await query.get();
  return snap.docs.map(sessionFromDoc);
}

export async function getSession(
  sessionId: string
): Promise<ImpersonationSession | null> {
  const doc = await getAdminDb()
    .collection("devImpersonationSessions")
    .doc(sessionId)
    .get();
  if (!doc.exists) return null;
  return sessionFromDoc(doc);
}

export async function listEvents(
  sessionId: string
): Promise<ImpersonationAuditEvent[]> {
  const snap = await getAdminDb()
    .collection("devImpersonationAudit")
    .where("sessionId", "==", sessionId)
    .orderBy("timestamp", "asc")
    .limit(5000)
    .get();
  return snap.docs.map(eventFromDoc);
}

/**
 * Build a CSV string for a single session: session metadata header rows
 * followed by every audit event in chronological order. Uses the shared
 * `toCsvString` helper so escaping matches other admin exports.
 *
 * Records a meta `audit_exported` event to the audit stream so every export
 * is itself traceable.
 */
export async function exportSessionAsCsv(params: {
  sessionId: string;
  performedBy: string;
  performedByEmail?: string;
}): Promise<string> {
  const session = await getSession(params.sessionId);
  if (!session) throw new Error("Session not found.");
  const events = await listEvents(params.sessionId);

  const headers = [
    "record_type",
    "timestamp",
    "eventType",
    "sessionId",
    "devUid",
    "devEmail",
    "targetSchoolId",
    "targetSchoolName",
    "targetUserId",
    "targetRole",
    "status",
    "reason",
    "details",
  ];

  const rows: Record<string, string | number | boolean | undefined | null>[] = [
    {
      record_type: "session",
      timestamp: session.startedAt,
      eventType: "",
      sessionId: session.id,
      devUid: session.devUid,
      devEmail: session.devEmail,
      targetSchoolId: session.targetSchoolId,
      targetSchoolName: session.targetSchoolName ?? "",
      targetUserId: session.targetUserId,
      targetRole: session.targetRole,
      status: session.status,
      reason: session.reason,
      details: JSON.stringify({
        expiresAt: session.expiresAt,
        endedAt: session.endedAt,
        endReason: session.endReason,
        clientInfo: session.clientInfo,
      }),
    },
  ];

  for (const e of events) {
    rows.push({
      record_type: "event",
      timestamp: e.timestamp,
      eventType: e.eventType,
      sessionId: e.sessionId,
      devUid: e.devUid,
      devEmail: e.devEmail,
      targetSchoolId: e.targetSchoolId,
      targetSchoolName: "",
      targetUserId: e.targetUserId,
      targetRole: "",
      status: "",
      reason: "",
      details: JSON.stringify(e.details ?? {}),
    });
  }

  // Meta-audit: every export is itself logged.
  await getAdminDb().collection("devImpersonationAudit").add({
    sessionId: params.sessionId,
    devUid: session.devUid,
    devEmail: session.devEmail,
    targetSchoolId: session.targetSchoolId,
    targetUserId: session.targetUserId,
    eventType: "audit_exported" as ImpersonationEventType,
    details: {
      superAdminUid: params.performedBy,
      superAdminEmail: params.performedByEmail ?? null,
      rowCount: events.length,
      viaLumiAdmin: true,
    },
    timestamp: FieldValue.serverTimestamp(),
  });

  return toCsvString(headers, rows);
}
