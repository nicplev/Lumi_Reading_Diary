import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {createHash} from "crypto";
import {isSuperAdmin} from "./super_admin";

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const SESSION_TTL_MINUTES = 30;
const SESSION_TTL_MS = SESSION_TTL_MINUTES * 60 * 1000;

const MAX_STARTS_PER_HOUR = 5;
const MAX_STARTS_PER_DAY = 20;

const MAX_ACTIVITY_EVENTS_PER_MINUTE = 120;
const MAX_AUDIT_EXPORTS_PER_HOUR = 10;

const MIN_REASON_CHARS = 20;
const MAX_REASON_CHARS = 500;

const COLL_SESSIONS = "devImpersonationSessions";
const COLL_AUDIT = "devImpersonationAudit";
const COLL_RATE = "devImpersonationRateLimits";
const COLL_DEV_ACCESS = "devAccessEmails";

// ─── Phase 5 hardening: App Check enforcement ────────────────────────────────
// Opt-in via the IMPERSONATION_APP_CHECK_ENFORCED env var (set to "true").
// When enabled, callables refuse requests without a valid App Check token.
// Leave off during the rollout window while clients are integrating App
// Check; flip to on once every caller is attested.
const APP_CHECK_ENFORCED = process.env.IMPERSONATION_APP_CHECK_ENFORCED === "true";

function impersonationRuntime(
  opts: Pick<functions.RuntimeOptions, "timeoutSeconds" | "memory">
): functions.RuntimeOptions {
  return {
    ...opts,
    enforceAppCheck: APP_CHECK_ENFORCED,
    // consumeAppCheckToken only matters for replay-protection; safe to
    // default on whenever enforcement is on.
    consumeAppCheckToken: APP_CHECK_ENFORCED,
  };
}

type SessionStatus = "active" | "ended" | "expired" | "revoked";

type EventType =
  | "session_started"
  | "session_ended"
  | "session_expired"
  | "session_revoked"
  | "screen_viewed"
  | "export_requested"
  | "write_blocked_client"
  | "audit_exported";

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

function db(): admin.firestore.Firestore {
  return admin.firestore();
}

export function hashEmail(email: string): string {
  return createHash("sha256")
    .update(email.trim().toLowerCase())
    .digest("hex");
}

function requireAuthed(
  context: functions.https.CallableContext
): {uid: string; email: string} {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Sign-in required."
    );
  }
  const email = (context.auth.token.email as string | undefined) ?? "";
  if (!email) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Auth token is missing an email claim."
    );
  }
  return {uid: context.auth.uid, email};
}

async function requireDevAccess(
  context: functions.https.CallableContext
): Promise<{uid: string; email: string; emailHash: string}> {
  const {uid, email} = requireAuthed(context);
  const emailHash = hashEmail(email);
  const snap = await db().collection(COLL_DEV_ACCESS).doc(emailHash).get();
  if (!snap.exists) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Developer access is required."
    );
  }
  return {uid, email, emailHash};
}

async function requireSuperAdminAuth(
  context: functions.https.CallableContext
): Promise<{uid: string; email: string}> {
  const authed = requireAuthed(context);
  if (!(await isSuperAdmin(authed.uid))) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Super-admin privilege is required."
    );
  }
  return authed;
}

function asString(value: unknown, field: string): string {
  if (typeof value !== "string") {
    throw new functions.https.HttpsError(
      "invalid-argument",
      `${field} must be a string.`
    );
  }
  return value;
}

function asNonEmptyString(value: unknown, field: string): string {
  const s = asString(value, field).trim();
  if (s.length === 0) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      `${field} must be non-empty.`
    );
  }
  return s;
}

function assertRole(value: unknown): "teacher" | "schoolAdmin" {
  const s = asNonEmptyString(value, "targetRole");
  if (s !== "teacher" && s !== "schoolAdmin") {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "targetRole must be 'teacher' or 'schoolAdmin'."
    );
  }
  return s;
}

function clientInfoFromContext(
  data: Record<string, unknown>,
  context: functions.https.CallableContext
): Record<string, unknown> {
  const raw = (data.clientInfo ?? {}) as Record<string, unknown>;
  // rawRequest may be undefined in emulator tests; tolerate.
  const ip =
    (context.rawRequest as unknown as {ip?: string} | undefined)?.ip ?? null;
  const userAgent =
    (context.rawRequest as unknown as {headers?: {[k: string]: string}} | undefined)
      ?.headers?.["user-agent"] ?? null;
  return {
    platform: typeof raw.platform === "string" ? raw.platform : null,
    appVersion: typeof raw.appVersion === "string" ? raw.appVersion : null,
    ip,
    userAgent,
  };
}

async function writeAuditEvent(params: {
  sessionId: string;
  devUid: string;
  devEmail: string;
  targetSchoolId: string;
  targetUserId: string;
  eventType: EventType;
  details?: Record<string, unknown>;
}): Promise<void> {
  await db()
    .collection(COLL_AUDIT)
    .add({
      sessionId: params.sessionId,
      devUid: params.devUid,
      devEmail: params.devEmail,
      targetSchoolId: params.targetSchoolId,
      targetUserId: params.targetUserId,
      eventType: params.eventType,
      details: params.details ?? {},
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
  functions.logger.info("impersonation.audit", {
    eventType: params.eventType,
    sessionId: params.sessionId,
    devUid: params.devUid,
    targetSchoolId: params.targetSchoolId,
  });
}

/**
 * Atomic rate-limit check + increment. Throws HttpsError('resource-exhausted')
 * if the developer has exceeded either the hourly or daily ceiling. Rolls
 * windows forward when their start timestamp is older than the window length.
 */
async function enforceRateLimit(devUid: string): Promise<void> {
  const ref = db().collection(COLL_RATE).doc(devUid);
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = admin.firestore.Timestamp.now();
    const nowMs = now.toMillis();
    const ONE_HOUR = 60 * 60 * 1000;
    const ONE_DAY = 24 * ONE_HOUR;

    const prev = snap.exists ? snap.data() ?? {} : {};
    let hourStartMs = (prev.hourStart as admin.firestore.Timestamp | undefined)?.toMillis() ?? 0;
    let hourCount = (prev.hourCount as number | undefined) ?? 0;
    let dayStartMs = (prev.dayStart as admin.firestore.Timestamp | undefined)?.toMillis() ?? 0;
    let dayCount = (prev.dayCount as number | undefined) ?? 0;

    if (nowMs - hourStartMs >= ONE_HOUR) {
      hourStartMs = nowMs;
      hourCount = 0;
    }
    if (nowMs - dayStartMs >= ONE_DAY) {
      dayStartMs = nowMs;
      dayCount = 0;
    }

    if (hourCount >= MAX_STARTS_PER_HOUR) {
      throw new functions.https.HttpsError(
        "resource-exhausted",
        `Hourly impersonation limit reached (${MAX_STARTS_PER_HOUR}).`
      );
    }
    if (dayCount >= MAX_STARTS_PER_DAY) {
      throw new functions.https.HttpsError(
        "resource-exhausted",
        `Daily impersonation limit reached (${MAX_STARTS_PER_DAY}).`
      );
    }

    tx.set(
      ref,
      {
        hourStart: admin.firestore.Timestamp.fromMillis(hourStartMs),
        hourCount: hourCount + 1,
        dayStart: admin.firestore.Timestamp.fromMillis(dayStartMs),
        dayCount: dayCount + 1,
      },
      {merge: true}
    );
  });
}

async function revokeActiveSessionsForDev(
  devUid: string,
  devEmail: string,
  endReason: string
): Promise<void> {
  const snap = await db()
    .collection(COLL_SESSIONS)
    .where("devUid", "==", devUid)
    .where("status", "==", "active")
    .get();
  if (snap.empty) return;
  const batch = db().batch();
  const endedAt = admin.firestore.FieldValue.serverTimestamp();
  for (const doc of snap.docs) {
    batch.update(doc.ref, {status: "revoked", endedAt, endReason});
  }
  await batch.commit();
  for (const doc of snap.docs) {
    const data = doc.data();
    await writeAuditEvent({
      sessionId: doc.id,
      devUid,
      devEmail,
      targetSchoolId: String(data.targetSchoolId ?? ""),
      targetUserId: String(data.targetUserId ?? ""),
      eventType: "session_revoked",
      details: {endReason},
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Callable: startImpersonationSession
// ─────────────────────────────────────────────────────────────────────────────

interface StartImpersonationInput {
  targetSchoolId?: unknown;
  targetUserId?: unknown;
  targetRole?: unknown;
  reason?: unknown;
  clientInfo?: unknown;
}

export const startImpersonationSession = functions
  .runWith(impersonationRuntime({timeoutSeconds: 30, memory: "256MB"}))
  .https.onCall(async (data: StartImpersonationInput, context) => {
    const {uid: devUid, email: devEmail} = await requireDevAccess(context);

    const targetSchoolId = asNonEmptyString(data.targetSchoolId, "targetSchoolId");
    const targetUserId = asNonEmptyString(data.targetUserId, "targetUserId");
    const targetRole = assertRole(data.targetRole);
    const reasonRaw = asString(data.reason, "reason");
    const reason = reasonRaw.trim();
    if (reason.length < MIN_REASON_CHARS) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        `reason must be at least ${MIN_REASON_CHARS} characters.`
      );
    }
    if (reason.length > MAX_REASON_CHARS) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        `reason must be ${MAX_REASON_CHARS} characters or fewer.`
      );
    }

    if (targetUserId === devUid) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Cannot impersonate yourself."
      );
    }

    const schoolSnap = await db().collection("schools").doc(targetSchoolId).get();
    if (!schoolSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Target school not found.");
    }
    const schoolData = schoolSnap.data() ?? {};
    if (schoolData.active === false) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Target school is offboarded."
      );
    }

    const userSnap = await db()
      .collection("schools").doc(targetSchoolId)
      .collection("users").doc(targetUserId)
      .get();
    if (!userSnap.exists) {
      throw new functions.https.HttpsError(
        "not-found",
        "Target user not found in school."
      );
    }
    const userData = userSnap.data() ?? {};
    if (userData.role !== targetRole) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        `Target user's role (${userData.role}) does not match requested role.`
      );
    }
    // Defensive: never impersonate a super-admin-typed user doc.
    if (userData.role === "superAdmin") {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Cannot impersonate a super-admin."
      );
    }

    await enforceRateLimit(devUid);
    await revokeActiveSessionsForDev(devUid, devEmail, "replaced_by_new_session");

    const sessionRef = db().collection(COLL_SESSIONS).doc();
    const sessionId = sessionRef.id;
    const now = admin.firestore.Timestamp.now();
    const expiresAt = admin.firestore.Timestamp.fromMillis(
      now.toMillis() + SESSION_TTL_MS
    );
    const devEmailHash = hashEmail(devEmail);
    const clientInfo = clientInfoFromContext(
      data as Record<string, unknown>,
      context
    );

    await sessionRef.set({
      devUid,
      devEmail,
      devEmailHash,
      targetSchoolId,
      targetSchoolName: schoolData.name ?? null,
      targetUserId,
      targetUserEmail: userData.email ?? null,
      targetRole,
      reason,
      status: "active" as SessionStatus,
      startedAt: now,
      expiresAt,
      endedAt: null,
      endReason: null,
      clientInfo,
    });

    await writeAuditEvent({
      sessionId,
      devUid,
      devEmail,
      targetSchoolId,
      targetUserId,
      eventType: "session_started",
      details: {targetRole, reason, clientInfo},
    });

    const customToken = await admin.auth().createCustomToken(devUid, {
      devImpersonating: true,
      impersonationSchoolId: targetSchoolId,
      impersonationUserId: targetUserId,
      impersonationRole: targetRole,
      impersonationSessionId: sessionId,
      devReadOnly: true,
      devUid,
      devEmail,
    });

    return {
      sessionId,
      customToken,
      expiresAt: expiresAt.toMillis(),
    };
  });

// ─────────────────────────────────────────────────────────────────────────────
// Callable: endImpersonationSession
// ─────────────────────────────────────────────────────────────────────────────

export const endImpersonationSession = functions
  .runWith(impersonationRuntime({timeoutSeconds: 15, memory: "128MB"}))
  .https.onCall(async (data: {sessionId?: unknown}, context) => {
    const {uid} = requireAuthed(context);
    const sessionId = asNonEmptyString(data.sessionId, "sessionId");

    const ref = db().collection(COLL_SESSIONS).doc(sessionId);
    const snap = await ref.get();
    if (!snap.exists) {
      throw new functions.https.HttpsError("not-found", "Session not found.");
    }
    const sd = snap.data() ?? {};

    const isOwner = sd.devUid === uid;
    const isSuper = await isSuperAdmin(uid);
    if (!isOwner && !isSuper) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Only the session owner or a super-admin can end this session."
      );
    }

    if (sd.status !== "active") {
      return {sessionId, status: sd.status};
    }

    await ref.update({
      status: "ended",
      endedAt: admin.firestore.FieldValue.serverTimestamp(),
      endReason: isOwner ? "owner_ended" : "super_admin_ended",
    });

    await writeAuditEvent({
      sessionId,
      devUid: String(sd.devUid),
      devEmail: String(sd.devEmail),
      targetSchoolId: String(sd.targetSchoolId ?? ""),
      targetUserId: String(sd.targetUserId ?? ""),
      eventType: "session_ended",
      details: {endedBy: isOwner ? "owner" : "super_admin", superAdminUid: isSuper ? uid : null},
    });

    return {sessionId, status: "ended"};
  });

// ─────────────────────────────────────────────────────────────────────────────
// Callable: revokeImpersonationSession (super-admin only)
// ─────────────────────────────────────────────────────────────────────────────

export const revokeImpersonationSession = functions
  .runWith(impersonationRuntime({timeoutSeconds: 15, memory: "128MB"}))
  .https.onCall(async (data: {sessionId?: unknown; reason?: unknown}, context) => {
    const {uid} = await requireSuperAdminAuth(context);
    const sessionId = asNonEmptyString(data.sessionId, "sessionId");
    const reason = asNonEmptyString(data.reason, "reason");

    const ref = db().collection(COLL_SESSIONS).doc(sessionId);
    const snap = await ref.get();
    if (!snap.exists) {
      throw new functions.https.HttpsError("not-found", "Session not found.");
    }
    const sd = snap.data() ?? {};
    if (sd.status !== "active") {
      return {sessionId, status: sd.status};
    }

    await ref.update({
      status: "revoked",
      endedAt: admin.firestore.FieldValue.serverTimestamp(),
      endReason: `revoked_by_super_admin: ${reason}`,
    });

    await writeAuditEvent({
      sessionId,
      devUid: String(sd.devUid),
      devEmail: String(sd.devEmail),
      targetSchoolId: String(sd.targetSchoolId ?? ""),
      targetUserId: String(sd.targetUserId ?? ""),
      eventType: "session_revoked",
      details: {superAdminUid: uid, reason},
    });

    return {sessionId, status: "revoked"};
  });

// ─────────────────────────────────────────────────────────────────────────────
// Callable: reportImpersonationActivity
// ─────────────────────────────────────────────────────────────────────────────

export const reportImpersonationActivity = functions
  .runWith(impersonationRuntime({timeoutSeconds: 10, memory: "128MB"}))
  .https.onCall(
    async (
      data: {sessionId?: unknown; eventType?: unknown; details?: unknown},
      context
    ) => {
      const {uid} = requireAuthed(context);
      const sessionId = asNonEmptyString(data.sessionId, "sessionId");
      const eventTypeRaw = asNonEmptyString(data.eventType, "eventType");
      const allowedFromClient: EventType[] = ["screen_viewed", "export_requested"];
      if (!allowedFromClient.includes(eventTypeRaw as EventType)) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "eventType is not reportable from the client."
        );
      }
      const eventType = eventTypeRaw as EventType;

      const ref = db().collection(COLL_SESSIONS).doc(sessionId);
      const snap = await ref.get();
      if (!snap.exists) {
        throw new functions.https.HttpsError("not-found", "Session not found.");
      }
      const sd = snap.data() ?? {};
      if (sd.devUid !== uid) {
        throw new functions.https.HttpsError(
          "permission-denied",
          "You do not own this session."
        );
      }
      if (sd.status !== "active") {
        throw new functions.https.HttpsError(
          "failed-precondition",
          `Session status is ${sd.status}.`
        );
      }

      // Per-session-per-minute ceiling to guard against log storms.
      const oneMinAgo = admin.firestore.Timestamp.fromMillis(Date.now() - 60_000);
      const recentCount = await db()
        .collection(COLL_AUDIT)
        .where("sessionId", "==", sessionId)
        .where("timestamp", ">=", oneMinAgo)
        .count()
        .get();
      if (recentCount.data().count >= MAX_ACTIVITY_EVENTS_PER_MINUTE) {
        throw new functions.https.HttpsError(
          "resource-exhausted",
          "Activity log rate limit exceeded."
        );
      }

      const details =
        typeof data.details === "object" && data.details !== null
          ? (data.details as Record<string, unknown>)
          : {};

      await writeAuditEvent({
        sessionId,
        devUid: String(sd.devUid),
        devEmail: String(sd.devEmail),
        targetSchoolId: String(sd.targetSchoolId ?? ""),
        targetUserId: String(sd.targetUserId ?? ""),
        eventType,
        details,
      });

      return {ok: true};
    }
  );

// ─────────────────────────────────────────────────────────────────────────────
// Callable: reportBlockedWrite
// ─────────────────────────────────────────────────────────────────────────────

export const reportBlockedWrite = functions
  .runWith(impersonationRuntime({timeoutSeconds: 10, memory: "128MB"}))
  .https.onCall(
    async (
      data: {
        sessionId?: unknown;
        collection?: unknown;
        docId?: unknown;
        operation?: unknown;
        reason?: unknown;
      },
      context
    ) => {
      const {uid} = requireAuthed(context);
      const sessionId = asNonEmptyString(data.sessionId, "sessionId");

      const ref = db().collection(COLL_SESSIONS).doc(sessionId);
      const snap = await ref.get();
      if (!snap.exists) {
        throw new functions.https.HttpsError("not-found", "Session not found.");
      }
      const sd = snap.data() ?? {};
      if (sd.devUid !== uid) {
        throw new functions.https.HttpsError(
          "permission-denied",
          "You do not own this session."
        );
      }

      await writeAuditEvent({
        sessionId,
        devUid: String(sd.devUid),
        devEmail: String(sd.devEmail),
        targetSchoolId: String(sd.targetSchoolId ?? ""),
        targetUserId: String(sd.targetUserId ?? ""),
        eventType: "write_blocked_client",
        details: {
          collection: typeof data.collection === "string" ? data.collection : null,
          docId: typeof data.docId === "string" ? data.docId : null,
          operation: typeof data.operation === "string" ? data.operation : null,
          reason: typeof data.reason === "string" ? data.reason : null,
        },
      });

      return {ok: true};
    }
  );

// ─────────────────────────────────────────────────────────────────────────────
// Callable: exportImpersonationAudit (super-admin only)
// ─────────────────────────────────────────────────────────────────────────────
//
// v1 behaviour: returns a CSV string directly so the lumi-admin server can
// stream it to the caller as a file download. Signed GCS URL flow is an
// explicit v2 follow-up if exports ever exceed the callable 10 MB payload cap.

interface ExportInput {
  sessionId?: unknown;
  devUid?: unknown;
  startDate?: unknown; // ISO 8601
  endDate?: unknown;
}

function csvEscape(value: unknown): string {
  if (value === null || value === undefined) return "";
  const s =
    typeof value === "object" ?
      JSON.stringify(value) :
      String(value);
  if (/[",\n\r]/.test(s)) {
    return `"${s.replace(/"/g, '""')}"`;
  }
  return s;
}

export const exportImpersonationAudit = functions
  .runWith(impersonationRuntime({timeoutSeconds: 60, memory: "512MB"}))
  .https.onCall(async (data: ExportInput, context) => {
    const {uid: superUid, email: superEmail} = await requireSuperAdminAuth(context);

    // Rate-limit exports: count meta-audit events in the last hour.
    const oneHourAgo = admin.firestore.Timestamp.fromMillis(Date.now() - 3600_000);
    const recentExports = await db()
      .collection(COLL_AUDIT)
      .where("eventType", "==", "audit_exported")
      .where("timestamp", ">=", oneHourAgo)
      .where("details.superAdminUid", "==", superUid)
      .count()
      .get();
    if (recentExports.data().count >= MAX_AUDIT_EXPORTS_PER_HOUR) {
      throw new functions.https.HttpsError(
        "resource-exhausted",
        `Export limit reached (${MAX_AUDIT_EXPORTS_PER_HOUR}/hour).`
      );
    }

    let q: admin.firestore.Query = db()
      .collection(COLL_AUDIT)
      .orderBy("timestamp", "asc");

    if (typeof data.sessionId === "string" && data.sessionId.length > 0) {
      q = q.where("sessionId", "==", data.sessionId);
    }
    if (typeof data.devUid === "string" && data.devUid.length > 0) {
      q = q.where("devUid", "==", data.devUid);
    }
    if (typeof data.startDate === "string" && data.startDate.length > 0) {
      const start = new Date(data.startDate);
      if (!isNaN(start.getTime())) {
        q = q.where("timestamp", ">=", admin.firestore.Timestamp.fromDate(start));
      }
    }
    if (typeof data.endDate === "string" && data.endDate.length > 0) {
      const end = new Date(data.endDate);
      if (!isNaN(end.getTime())) {
        q = q.where("timestamp", "<=", admin.firestore.Timestamp.fromDate(end));
      }
    }

    const snap = await q.limit(10000).get();

    const headers = [
      "timestamp",
      "eventType",
      "sessionId",
      "devUid",
      "devEmail",
      "targetSchoolId",
      "targetUserId",
      "details",
    ];
    const rows: string[] = [headers.join(",")];
    for (const doc of snap.docs) {
      const d = doc.data();
      const ts = d.timestamp instanceof admin.firestore.Timestamp ?
        d.timestamp.toDate().toISOString() :
        "";
      rows.push(
        [
          csvEscape(ts),
          csvEscape(d.eventType),
          csvEscape(d.sessionId),
          csvEscape(d.devUid),
          csvEscape(d.devEmail),
          csvEscape(d.targetSchoolId),
          csvEscape(d.targetUserId),
          csvEscape(d.details ?? {}),
        ].join(",")
      );
    }

    // Meta-audit the export itself so super-admin activity is visible in the
    // same stream.
    await db().collection(COLL_AUDIT).add({
      sessionId: typeof data.sessionId === "string" ? data.sessionId : "",
      devUid: typeof data.devUid === "string" ? data.devUid : "",
      devEmail: "",
      targetSchoolId: "",
      targetUserId: "",
      eventType: "audit_exported" as EventType,
      details: {
        superAdminUid: superUid,
        superAdminEmail: superEmail,
        rowCount: snap.size,
        filters: {
          sessionId: typeof data.sessionId === "string" ? data.sessionId : null,
          devUid: typeof data.devUid === "string" ? data.devUid : null,
          startDate: typeof data.startDate === "string" ? data.startDate : null,
          endDate: typeof data.endDate === "string" ? data.endDate : null,
        },
      },
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {csv: rows.join("\n"), rowCount: snap.size};
  });

// ─────────────────────────────────────────────────────────────────────────────
// Callable: listImpersonableSchools (dev-access only)
// ─────────────────────────────────────────────────────────────────────────────
//
// Powers the picker UX. Returns active schools with a safe summary shape.
// We do NOT widen Firestore rules for devs to list /schools directly — going
// through a callable keeps the surface area tight.

export const listImpersonableSchools = functions
  .runWith(impersonationRuntime({timeoutSeconds: 15, memory: "256MB"}))
  .https.onCall(async (_data, context) => {
    await requireDevAccess(context);

    const snap = await db()
      .collection("schools")
      .orderBy("name")
      .limit(200)
      .get();

    const items: Array<Record<string, unknown>> = [];
    for (const doc of snap.docs) {
      const d = doc.data();
      if (d.active === false) continue;
      items.push({
        schoolId: doc.id,
        name: String(d.name ?? ""),
        teacherCount: typeof d.teacherCount === "number" ? d.teacherCount : 0,
      });
    }
    return {schools: items};
  });

// ─────────────────────────────────────────────────────────────────────────────
// Callable: listImpersonableUsers (dev-access only)
// ─────────────────────────────────────────────────────────────────────────────

interface ListUsersInput {
  schoolId?: unknown;
  role?: unknown; // 'teacher' | 'schoolAdmin'
}

export const listImpersonableUsers = functions
  .runWith(impersonationRuntime({timeoutSeconds: 15, memory: "256MB"}))
  .https.onCall(async (data: ListUsersInput, context) => {
    await requireDevAccess(context);
    const schoolId = asNonEmptyString(data.schoolId, "schoolId");
    const role = assertRole(data.role);

    const snap = await db()
      .collection("schools").doc(schoolId)
      .collection("users")
      .where("role", "==", role)
      .limit(500)
      .get();

    const items: Array<Record<string, unknown>> = [];
    for (const doc of snap.docs) {
      const d = doc.data();
      // Defence-in-depth: never expose a superAdmin-typed row if one leaks in.
      if (d.role === "superAdmin") continue;
      // Skip deactivated accounts by convention if flagged.
      if (d.isActive === false) continue;
      items.push({
        userId: doc.id,
        email: String(d.email ?? ""),
        fullName: String(d.fullName ?? ""),
        role: String(d.role ?? role),
      });
    }
    return {users: items};
  });

// ─────────────────────────────────────────────────────────────────────────────
// Scheduled: expireImpersonationSessions
// ─────────────────────────────────────────────────────────────────────────────

export const expireImpersonationSessions = functions.pubsub
  .schedule("every 5 minutes")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();
    const snap = await db()
      .collection(COLL_SESSIONS)
      .where("status", "==", "active")
      .where("expiresAt", "<=", now)
      .limit(500)
      .get();

    if (snap.empty) {
      return null;
    }

    const batch = db().batch();
    for (const doc of snap.docs) {
      batch.update(doc.ref, {
        status: "expired",
        endedAt: admin.firestore.FieldValue.serverTimestamp(),
        endReason: "ttl_expired",
      });
    }
    await batch.commit();

    for (const doc of snap.docs) {
      const d = doc.data();
      await writeAuditEvent({
        sessionId: doc.id,
        devUid: String(d.devUid),
        devEmail: String(d.devEmail),
        targetSchoolId: String(d.targetSchoolId ?? ""),
        targetUserId: String(d.targetUserId ?? ""),
        eventType: "session_expired",
        details: {expiredAt: now.toDate().toISOString()},
      });
    }

    functions.logger.info("impersonation.expired", {count: snap.size});
    return null;
  });

// ─────────────────────────────────────────────────────────────────────────────
// Trigger: onDelete(devAccessEmails/{hash}) → revoke active sessions
// ─────────────────────────────────────────────────────────────────────────────

export const revokeOnDevAccessRemoval = functions.firestore
  .document("devAccessEmails/{emailHash}")
  .onDelete(async (_snap, context) => {
    const emailHash = context.params.emailHash as string;
    const q = await db()
      .collection(COLL_SESSIONS)
      .where("devEmailHash", "==", emailHash)
      .where("status", "==", "active")
      .get();
    if (q.empty) {
      return null;
    }
    const batch = db().batch();
    const endedAt = admin.firestore.FieldValue.serverTimestamp();
    for (const doc of q.docs) {
      batch.update(doc.ref, {
        status: "revoked",
        endedAt,
        endReason: "dev_access_revoked",
      });
    }
    await batch.commit();
    for (const doc of q.docs) {
      const d = doc.data();
      await writeAuditEvent({
        sessionId: doc.id,
        devUid: String(d.devUid),
        devEmail: String(d.devEmail),
        targetSchoolId: String(d.targetSchoolId ?? ""),
        targetUserId: String(d.targetUserId ?? ""),
        eventType: "session_revoked",
        details: {endReason: "dev_access_revoked"},
      });
    }
    functions.logger.info("impersonation.revoked_on_dev_access_removal", {
      emailHash,
      count: q.size,
    });
    return null;
  });

// ─────────────────────────────────────────────────────────────────────────────
// Scheduled: monitorImpersonationAnomalies
// ─────────────────────────────────────────────────────────────────────────────
//
// Runs hourly. For each developer that started at least one session in the
// last hour, counts the number of distinct schools impersonated and the
// number of session starts. Anything exceeding the thresholds below emits a
// structured WARNING log which Cloud Monitoring can be wired to alert on.
//
// Intentionally conservative: the per-caller rate limit enforced inside
// startImpersonationSession is the hard ceiling (5/hr, 20/day). These
// thresholds are LOWER so they fire as a "pay attention" signal well before
// the rate limit would reject.

const ANOMALY_SCHOOLS_PER_HOUR = 5;
const ANOMALY_SESSIONS_PER_HOUR = 4;

export const monitorImpersonationAnomalies = functions.pubsub
  .schedule("every 60 minutes")
  .onRun(async () => {
    const oneHourAgo = admin.firestore.Timestamp.fromMillis(
      Date.now() - 60 * 60 * 1000
    );

    const snap = await db()
      .collection(COLL_SESSIONS)
      .where("startedAt", ">=", oneHourAgo)
      .limit(500)
      .get();

    if (snap.empty) {
      return null;
    }

    // Group by devUid → { sessionCount, schoolIds }.
    const perDev = new Map<
      string,
      {devEmail: string; count: number; schools: Set<string>}
    >();
    for (const doc of snap.docs) {
      const d = doc.data();
      const devUid = String(d.devUid ?? "");
      if (!devUid) continue;
      const entry = perDev.get(devUid) ?? {
        devEmail: String(d.devEmail ?? ""),
        count: 0,
        schools: new Set<string>(),
      };
      entry.count += 1;
      if (d.targetSchoolId) entry.schools.add(String(d.targetSchoolId));
      perDev.set(devUid, entry);
    }

    let flagged = 0;
    for (const [devUid, info] of perDev.entries()) {
      const schoolCount = info.schools.size;
      const exceedsSchools = schoolCount >= ANOMALY_SCHOOLS_PER_HOUR;
      const exceedsSessions = info.count >= ANOMALY_SESSIONS_PER_HOUR;
      if (!exceedsSchools && !exceedsSessions) continue;

      flagged++;
      functions.logger.warn("impersonation.anomaly", {
        eventType: "impersonation.anomaly",
        devUid,
        devEmail: info.devEmail,
        windowMinutes: 60,
        sessionCount: info.count,
        schoolCount,
        schools: Array.from(info.schools),
        thresholds: {
          schoolsPerHour: ANOMALY_SCHOOLS_PER_HOUR,
          sessionsPerHour: ANOMALY_SESSIONS_PER_HOUR,
        },
        triggered: {
          schools: exceedsSchools,
          sessions: exceedsSessions,
        },
      });
    }

    functions.logger.info("impersonation.anomaly_sweep", {
      devsScanned: perDev.size,
      flagged,
    });
    return null;
  });
