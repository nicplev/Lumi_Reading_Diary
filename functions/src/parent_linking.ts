import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

const fns = functions.region("australia-southeast1");

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const MAX_LINKS_PER_HOUR = 10;
const MAX_LINKS_PER_DAY = 30;

const COLL_RATE = "parentLinkingRateLimits";
const COLL_LINK_CODES = "studentLinkCodes";

// App Check enforcement, opt-in via env var. Default off because this fires
// during account creation — a half-rolled-out App Check would lock new
// parents out. Flip via PARENT_LINKING_APP_CHECK_ENFORCED=true once Flutter
// attestation rollout is verified.
const APP_CHECK_ENFORCED =
  process.env.PARENT_LINKING_APP_CHECK_ENFORCED === "true";

function parentLinkingRuntime(
  opts: Pick<functions.RuntimeOptions, "timeoutSeconds" | "memory">
): functions.RuntimeOptions {
  return {
    ...opts,
    enforceAppCheck: APP_CHECK_ENFORCED,
    consumeAppCheckToken: APP_CHECK_ENFORCED,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

function db(): admin.firestore.Firestore {
  return admin.firestore();
}

function requireAuthed(
  context: functions.https.CallableContext
): {uid: string; email: string | null} {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Sign-in required."
    );
  }
  const email = (context.auth.token.email as string | undefined) ?? null;
  return {uid: context.auth.uid, email};
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

function asOptionalString(value: unknown, field: string): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") {
    throw new functions.https.HttpsError(
      "invalid-argument",
      `${field} must be a string when provided.`
    );
  }
  const trimmed = value.trim();
  return trimmed.length === 0 ? null : trimmed;
}

// Atomic rate-limit check + increment for the calling parent. Mirrors
// `enforceRateLimit` in impersonation.ts so we get the same hour/day window
// behaviour. Throws HttpsError('resource-exhausted') if either ceiling is hit.
async function enforceRateLimit(uid: string): Promise<void> {
  const ref = db().collection(COLL_RATE).doc(uid);
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = admin.firestore.Timestamp.now();
    const nowMs = now.toMillis();
    const ONE_HOUR = 60 * 60 * 1000;
    const ONE_DAY = 24 * ONE_HOUR;

    const prev = snap.exists ? snap.data() ?? {} : {};
    let hourStartMs =
      (prev.hourStart as admin.firestore.Timestamp | undefined)?.toMillis() ??
      0;
    let hourCount = (prev.hourCount as number | undefined) ?? 0;
    let dayStartMs =
      (prev.dayStart as admin.firestore.Timestamp | undefined)?.toMillis() ?? 0;
    let dayCount = (prev.dayCount as number | undefined) ?? 0;

    if (nowMs - hourStartMs >= ONE_HOUR) {
      hourStartMs = nowMs;
      hourCount = 0;
    }
    if (nowMs - dayStartMs >= ONE_DAY) {
      dayStartMs = nowMs;
      dayCount = 0;
    }

    if (hourCount >= MAX_LINKS_PER_HOUR) {
      throw new functions.https.HttpsError(
        "resource-exhausted",
        `Hourly link limit reached (${MAX_LINKS_PER_HOUR}).`
      );
    }
    if (dayCount >= MAX_LINKS_PER_DAY) {
      throw new functions.https.HttpsError(
        "resource-exhausted",
        `Daily link limit reached (${MAX_LINKS_PER_DAY}).`
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

type LinkCodeStatus = "active" | "used" | "revoked" | "expired";

interface LinkCodeRecord {
  id: string;
  code: string;
  status: LinkCodeStatus | string;
  studentId: string;
  schoolId: string;
  expiresAt: Date | null;
  revokeReason: string | null;
}

function parseExpiresAt(raw: unknown): Date | null {
  if (raw instanceof admin.firestore.Timestamp) return raw.toDate();
  if (raw instanceof Date) return raw;
  if (typeof raw === "string") {
    const d = new Date(raw);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

function parseCodeDoc(
  snap: FirebaseFirestore.QueryDocumentSnapshot | FirebaseFirestore.DocumentSnapshot
): LinkCodeRecord {
  const data = snap.data() ?? {};
  return {
    id: snap.id,
    code: String(data.code ?? "").toUpperCase(),
    status: (data.status as string) ?? "",
    studentId: String(data.studentId ?? ""),
    schoolId: String(data.schoolId ?? ""),
    expiresAt: parseExpiresAt(data.expiresAt ?? data.expiryDate),
    revokeReason: (data.revokeReason as string | null | undefined) ?? null,
  };
}

// Priority order for picking the best record when multiple codes share the
// same string. Mirrors `_priorityForCode` in
// lib/services/parent_linking_service.dart — active wins, then used, then
// revoked, then expired.
function codePriority(rec: LinkCodeRecord): number {
  const now = new Date();
  const expired = rec.expiresAt !== null && rec.expiresAt < now;
  if (rec.status === "active" && !expired) return 0;
  if (rec.status === "used") return 1;
  if (rec.status === "revoked") return 2;
  if (rec.status === "expired" || expired) return 3;
  return 4;
}

async function findBestCodeForString(
  codeUpper: string
): Promise<LinkCodeRecord | null> {
  const query = await db()
    .collection(COLL_LINK_CODES)
    .where("code", "==", codeUpper)
    .limit(10)
    .get();
  if (query.empty) return null;

  const parsed = query.docs.map(parseCodeDoc);
  parsed.sort((a, b) => {
    const pa = codePriority(a);
    const pb = codePriority(b);
    if (pa !== pb) return pa - pb;
    return 0;
  });
  return parsed[0];
}

function failedPrecondition(kind: string, message: string, extra?: Record<string, unknown>) {
  return new functions.https.HttpsError("failed-precondition", message, {
    kind,
    ...(extra ?? {}),
  });
}

function notFound(kind: string, message: string) {
  return new functions.https.HttpsError("not-found", message, {kind});
}

function alreadyExists(kind: string, message: string) {
  return new functions.https.HttpsError("already-exists", message, {kind});
}

function permissionDenied(message: string) {
  return new functions.https.HttpsError("permission-denied", message);
}

// ─────────────────────────────────────────────────────────────────────────────
// Callable: linkParentToStudent
// ─────────────────────────────────────────────────────────────────────────────

interface LinkParentInput {
  code?: unknown;
  clientInfo?: unknown;
}

export const linkParentToStudent = fns
  .runWith(parentLinkingRuntime({timeoutSeconds: 30, memory: "256MB"}))
  .https.onCall(async (data: LinkParentInput, context) => {
    const {uid} = requireAuthed(context);
    const codeUpper = asNonEmptyString(data.code, "code").toUpperCase();

    await enforceRateLimit(uid);

    const best = await findBestCodeForString(codeUpper);
    if (!best) {
      throw failedPrecondition("invalid-code", "Link code not recognised.");
    }

    return db().runTransaction(async (tx) => {
      // 1. Re-read inside the transaction (TOCTOU defense).
      const codeRef = db().collection(COLL_LINK_CODES).doc(best.id);
      const codeSnap = await tx.get(codeRef);
      if (!codeSnap.exists) {
        throw failedPrecondition("invalid-code", "Link code not recognised.");
      }
      const fresh = parseCodeDoc(codeSnap);
      if (fresh.code !== codeUpper) {
        throw failedPrecondition("invalid-code", "Link code not recognised.");
      }
      if (fresh.status === "used") {
        throw failedPrecondition("code-used", "This code has already been used.");
      }
      if (fresh.status === "revoked") {
        throw failedPrecondition(
          "code-revoked",
          "This code has been revoked.",
          fresh.revokeReason !== null ? {reason: fresh.revokeReason} : undefined
        );
      }
      if (fresh.expiresAt === null) {
        throw failedPrecondition("invalid-code", "Link code is malformed.");
      }
      if (fresh.status === "expired" || fresh.expiresAt < new Date()) {
        throw failedPrecondition("code-expired", "This code has expired.");
      }
      if (fresh.status !== "active") {
        throw failedPrecondition("invalid-code", "Link code is not active.");
      }
      if (fresh.schoolId.length === 0 || fresh.studentId.length === 0) {
        throw failedPrecondition("invalid-code", "Link code is malformed.");
      }

      // 2. Parent doc must already exist — the client creates it before
      //    calling this. Server never forks doc-shape ownership.
      const parentRef = db()
        .collection("schools").doc(fresh.schoolId)
        .collection("parents").doc(uid);
      const parentSnap = await tx.get(parentRef);
      if (!parentSnap.exists) {
        throw failedPrecondition(
          "parent-doc-missing",
          "Parent profile must exist before linking."
        );
      }

      const studentRef = db()
        .collection("schools").doc(fresh.schoolId)
        .collection("students").doc(fresh.studentId);
      const studentSnap = await tx.get(studentRef);
      if (!studentSnap.exists) {
        throw notFound("student-missing", "Student not found.");
      }

      const existingLinked = Array.isArray(parentSnap.data()?.linkedChildren) ?
        (parentSnap.data()?.linkedChildren as string[]) :
        [];
      if (existingLinked.includes(fresh.studentId)) {
        throw alreadyExists("already-linked", "Already linked to this student.");
      }

      // 3. Atomic writes.
      tx.update(studentRef, {
        parentIds: admin.firestore.FieldValue.arrayUnion(uid),
      });
      tx.set(
        parentRef,
        {
          linkedChildren: admin.firestore.FieldValue.arrayUnion(fresh.studentId),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
      tx.update(codeRef, {
        status: "used",
        usedBy: uid,
        usedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Return projected fresh linkedChildren so the client can skip a
      // follow-up read.
      const projectedLinked = [...existingLinked, fresh.studentId];
      return {
        studentId: fresh.studentId,
        schoolId: fresh.schoolId,
        linkedChildren: projectedLinked,
      };
    });
  });

// ─────────────────────────────────────────────────────────────────────────────
// Callable: unlinkParentFromStudent
// ─────────────────────────────────────────────────────────────────────────────

interface UnlinkParentInput {
  schoolId?: unknown;
  studentId?: unknown;
  parentUserId?: unknown;
  reason?: unknown;
}

async function callerCanUnlink(
  uid: string,
  schoolId: string,
  parentUserId: string
): Promise<boolean> {
  if (uid === parentUserId) return true;
  // Teacher / school admin in this school can also unlink.
  const userSnap = await db()
    .collection("schools").doc(schoolId)
    .collection("users").doc(uid)
    .get();
  if (!userSnap.exists) return false;
  const role = (userSnap.data()?.role as string | undefined) ?? "";
  return role === "teacher" || role === "schoolAdmin";
}

export const unlinkParentFromStudent = fns
  .runWith(parentLinkingRuntime({timeoutSeconds: 15, memory: "256MB"}))
  .https.onCall(async (data: UnlinkParentInput, context) => {
    const {uid} = requireAuthed(context);
    const schoolId = asNonEmptyString(data.schoolId, "schoolId");
    const studentId = asNonEmptyString(data.studentId, "studentId");
    const parentUserId = asNonEmptyString(data.parentUserId, "parentUserId");
    asOptionalString(data.reason, "reason"); // validate type only

    if (!(await callerCanUnlink(uid, schoolId, parentUserId))) {
      throw permissionDenied(
        "Only the parent themselves or a teacher/admin in the school may unlink."
      );
    }

    return db().runTransaction(async (tx) => {
      const studentRef = db()
        .collection("schools").doc(schoolId)
        .collection("students").doc(studentId);
      const parentRef = db()
        .collection("schools").doc(schoolId)
        .collection("parents").doc(parentUserId);

      const [studentSnap, parentSnap] = await Promise.all([
        tx.get(studentRef),
        tx.get(parentRef),
      ]);

      if (!studentSnap.exists) {
        throw notFound("student-missing", "Student not found.");
      }
      if (!parentSnap.exists) {
        throw failedPrecondition(
          "parent-doc-missing",
          "Parent profile not found."
        );
      }

      const parentIds = Array.isArray(studentSnap.data()?.parentIds) ?
        (studentSnap.data()?.parentIds as string[]) :
        [];
      if (!parentIds.includes(parentUserId)) {
        throw failedPrecondition(
          "not-linked",
          "Parent is not linked to this student."
        );
      }

      tx.update(studentRef, {
        parentIds: admin.firestore.FieldValue.arrayRemove(parentUserId),
      });
      tx.update(parentRef, {
        linkedChildren: admin.firestore.FieldValue.arrayRemove(studentId),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {schoolId, studentId, removedParentUid: parentUserId};
    });
  });
