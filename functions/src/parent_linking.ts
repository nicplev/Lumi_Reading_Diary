import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import {assertNotReadOnly} from "./read_only_guard";
import {buildStudentAccess, isActiveSubscriptionStatus} from "./access";

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

// Shared validation ladder for a link-code record. Throws the same typed
// `failed-precondition` errors (with `kind`) that the Flutter client decodes in
// `_mapHttpsError` (parent_linking_service.dart). Used by both the redeem
// transaction and the read-only verify callable so the two never drift.
function assertLinkCodeUsable(fresh: LinkCodeRecord): void {
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
}

function permissionDenied(message: string) {
  return new functions.https.HttpsError("permission-denied", message);
}

/**
 * Whether a student doc already carries live (active, unexpired) access.
 * @param {FirebaseFirestore.DocumentData|undefined} studentData Student doc data.
 * @return {boolean} True when access.status is active and not yet expired.
 */
function studentAccessAlreadyLive(
  studentData: FirebaseFirestore.DocumentData | undefined,
): boolean {
  const access = studentData?.access as Record<string, unknown> | undefined;
  if (!access || access.status !== "active") return false;
  const exp = access.expiresAt;
  const expMs =
    exp instanceof admin.firestore.Timestamp ?
      exp.toMillis() :
      exp instanceof Date ?
        exp.getTime() :
        0;
  return expMs > Date.now();
}

// ─────────────────────────────────────────────────────────────────────────────
// Callable: linkParentToStudent
// ─────────────────────────────────────────────────────────────────────────────

interface LinkParentInput {
  code?: unknown;
  clientInfo?: unknown;
}

/**
 * Core parent↔student link logic, shared by the [linkParentToStudent] callable
 * and the server-side MFA signup finaliser (enrollLinkedPhoneAsMfa). Validates
 * the code and atomically links parent↔student, granting book-pack access on
 * first link. The parent doc must already exist.
 * @param {string} uid The parent's Firebase UID.
 * @param {string} codeUpper The uppercased link code.
 * @return {Promise<{studentId: string, schoolId: string, linkedChildren: string[]}>}
 *   The linked student id, school id, and projected linkedChildren.
 */
export async function linkParentToStudentCore(
  uid: string,
  codeUpper: string,
): Promise<{studentId: string; schoolId: string; linkedChildren: string[]}> {
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
    assertLinkCodeUsable(fresh);

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

    // T3 — materialise access on first link. If the student has no live
    // access yet and the school's subscription for the current year is
    // active, grant book-pack-assumed access through end-of-January. Keeps a
    // new mid-year student in sync with the cohort. All reads happen before
    // any write (Firestore transaction rule).
    const cfgSnap = await tx.get(
      db().collection("config").doc("academicYear"),
    );
    const currentYear = cfgSnap.data()?.currentAcademicYear as
        | number
        | undefined;
    let subActive = false;
    if (typeof currentYear === "number") {
      const subSnap = await tx.get(
        db()
          .collection("schoolSubscriptions")
          .doc(`${fresh.schoolId}_${currentYear}`),
      );
      subActive =
          subSnap.exists &&
          isActiveSubscriptionStatus(subSnap.data()?.status as string);
    }
    const grantAccess =
        typeof currentYear === "number" &&
        subActive &&
        !studentAccessAlreadyLive(studentSnap.data());

    const existingLinked = Array.isArray(parentSnap.data()?.linkedChildren) ?
      (parentSnap.data()?.linkedChildren as string[]) :
      [];
    if (existingLinked.includes(fresh.studentId)) {
      throw alreadyExists("already-linked", "Already linked to this student.");
    }

    // 3. Atomic writes.
    const studentUpdate: admin.firestore.UpdateData<admin.firestore.DocumentData> = {
      parentIds: admin.firestore.FieldValue.arrayUnion(uid),
    };
    if (grantAccess) {
      studentUpdate.access = buildStudentAccess({
        academicYear: currentYear as number,
        source: "book_pack_assumed",
        grantedBy: uid,
      });
    }
    tx.update(studentRef, studentUpdate);
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
}

/**
 * Resolves the school (and student) a link code belongs to, running the shared
 * validity ladder. Server-side signup finalisation (enrollLinkedPhoneAsMfa)
 * DERIVES the parent's schoolId from the code they present rather than trusting
 * a client-supplied `schoolId`, so a caller can't create a parent membership in
 * an arbitrary school. Read-only — the redeem/consume still happens in
 * [linkParentToStudentCore].
 * @param {string} codeUpper The uppercased link code.
 * @return {Promise<{schoolId: string, studentId: string}>} The code's school
 *   and student ids.
 */
export async function resolveLinkCodeSchool(
  codeUpper: string,
): Promise<{schoolId: string; studentId: string}> {
  const best = await findBestCodeForString(codeUpper);
  if (!best) {
    throw failedPrecondition("invalid-code", "Link code not recognised.");
  }
  assertLinkCodeUsable(best);
  return {schoolId: best.schoolId, studentId: best.studentId};
}

export const linkParentToStudent = fns
  .runWith(parentLinkingRuntime({timeoutSeconds: 30, memory: "256MB"}))
  .https.onCall(async (data: LinkParentInput, context) => {
    assertNotReadOnly(context);
    const {uid} = requireAuthed(context);
    const codeUpper = asNonEmptyString(data.code, "code").toUpperCase();
    await enforceRateLimit(uid);
    return linkParentToStudentCore(uid, codeUpper);
  });

// ─────────────────────────────────────────────────────────────────────────────
// Callable: verifyStudentLinkCode  (read-only, exact-code lookup)
// ─────────────────────────────────────────────────────────────────────────────
//
// Replaces the client-side `where('code','==',x)` query the Flutter app used to
// run against `studentLinkCodes` (which required an unauthenticated `list` rule
// that let anyone paginate and harvest every child-link code). This callable
// looks a code up by EXACT value and returns only that one record's public
// fields — no enumeration is possible.
//
// Intentionally UNAUTHENTICATED: the parent app verifies a code at the very
// start of registration, before the account exists (see parent_registration_
// modal.dart). It throws the same typed `failed-precondition` errors (with
// `kind`) as the redeem path, so the client's existing `_mapHttpsError` handles
// expired/used/revoked/invalid identically.
export const verifyStudentLinkCode = fns
  .runWith(parentLinkingRuntime({timeoutSeconds: 15, memory: "128MB"}))
  .https.onCall(async (data: {code?: unknown}) => {
    const codeUpper = asNonEmptyString(data?.code, "code").toUpperCase();
    const best = await findBestCodeForString(codeUpper);
    if (!best) {
      throw failedPrecondition("invalid-code", "Link code not recognised.");
    }
    assertLinkCodeUsable(best);

    // Re-read the winning doc for the fields the confirmation UI needs
    // (student name lives in `metadata`), which `parseCodeDoc` doesn't carry.
    const snap = await db().collection(COLL_LINK_CODES).doc(best.id).get();
    const raw = snap.data() ?? {};
    const metadata =
      raw.metadata && typeof raw.metadata === "object" ?
        (raw.metadata as Record<string, unknown>) :
        {};

    return {
      ok: true,
      id: best.id,
      code: best.code,
      studentId: best.studentId,
      schoolId: best.schoolId,
      expiresAt: best.expiresAt ? best.expiresAt.toISOString() : null,
      metadata,
    };
  });

// ─────────────────────────────────────────────────────────────────────────────
// Callable: createCoParentInvite  (parent generates a co-parent invite code)
// ─────────────────────────────────────────────────────────────────────────────
//
// Moves co-parent-invite code generation server-side. The client used to
// generate the code and write the `studentLinkCodes` doc directly, which
// required (a) a client `where('code','==',x)` uniqueness read — served only by
// the unauthenticated `list` rule (the enumeration hole) — and (b) a parent
// client-create branch in the rules. This callable does both with the Admin SDK
// (bypassing rules) after verifying the caller is a parent LINKED to the target
// student, so those rule allowances can be removed.

// Excludes visually-similar chars (mirrors _generateCode in the Flutter app).
const LINK_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function generateCandidateCode(): string {
  let s = "";
  for (let i = 0; i < 8; i++) {
    s += LINK_CODE_ALPHABET.charAt(
      Math.floor(Math.random() * LINK_CODE_ALPHABET.length)
    );
  }
  return s;
}

async function generateUniqueLinkCode(): Promise<string> {
  for (let attempt = 0; attempt < 40; attempt++) {
    const candidate = generateCandidateCode();
    const existing = await db()
      .collection(COLL_LINK_CODES)
      .where("code", "==", candidate)
      .limit(1)
      .get();
    if (existing.empty) return candidate;
  }
  throw new functions.https.HttpsError(
    "resource-exhausted",
    "Could not generate a unique link code."
  );
}

interface CreateCoParentInviteInput {
  schoolId?: unknown;
  studentId?: unknown;
  note?: unknown;
  validityDays?: unknown;
}

export const createCoParentInvite = fns
  .runWith(parentLinkingRuntime({timeoutSeconds: 30, memory: "256MB"}))
  .https.onCall(async (data: CreateCoParentInviteInput, context) => {
    assertNotReadOnly(context);
    const {uid} = requireAuthed(context);
    const schoolId = asNonEmptyString(data.schoolId, "schoolId");
    const studentId = asNonEmptyString(data.studentId, "studentId");
    const note = asOptionalString(data.note, "note");
    const validityDays =
      typeof data.validityDays === "number" &&
      data.validityDays > 0 &&
      data.validityDays <= 3650 ?
        Math.floor(data.validityDays) :
        365;

    await enforceRateLimit(uid);

    // Authorization: caller must be a parent of this school linked to the
    // target student. Mirrors the old rules guard (parent member + already
    // linked to studentId), now enforced server-side.
    const parentSnap = await db()
      .collection("schools").doc(schoolId)
      .collection("parents").doc(uid)
      .get();
    if (!parentSnap.exists) {
      throw permissionDenied(
        "Only a linked parent can create a co-parent invite."
      );
    }
    const linkedChildren = Array.isArray(parentSnap.data()?.linkedChildren) ?
      (parentSnap.data()?.linkedChildren as string[]) :
      [];
    if (!linkedChildren.includes(studentId)) {
      throw permissionDenied("You are not linked to this student.");
    }

    // Student metadata so the invited co-parent sees the child's name.
    const studentRef = db()
      .collection("schools").doc(schoolId)
      .collection("students").doc(studentId);
    const studentSnap = await studentRef.get();
    if (!studentSnap.exists) {
      throw notFound("student-missing", "Student not found.");
    }
    const s = studentSnap.data() ?? {};
    const firstName = typeof s.firstName === "string" ? s.firstName : "";
    const lastName = typeof s.lastName === "string" ? s.lastName : "";
    const metadata = {
      studentFirstName: firstName,
      studentLastName: lastName,
      studentFullName: `${firstName} ${lastName}`.trim(),
    };

    const code = await generateUniqueLinkCode();
    const now = admin.firestore.Timestamp.now();
    const expiresAt = admin.firestore.Timestamp.fromMillis(
      now.toMillis() + validityDays * 24 * 60 * 60 * 1000
    );

    // Supersede existing active co_parent_invite codes for this student (one
    // active invite per student). Staff-issued codes are a different channel
    // and are left untouched — mirrors createLinkCode's supersede policy.
    const activeSnap = await db()
      .collection(COLL_LINK_CODES)
      .where("studentId", "==", studentId)
      .where("status", "==", "active")
      .limit(10)
      .get();

    const batch = db().batch();
    for (const doc of activeSnap.docs) {
      const intendedFor =
        (doc.data().intendedFor as string | undefined) ?? "staff_issued";
      if (intendedFor !== "co_parent_invite") continue;
      batch.update(doc.ref, {
        status: "revoked",
        revokedBy: uid,
        revokedAt: admin.firestore.FieldValue.serverTimestamp(),
        revokeReason: "Superseded by newly generated link code",
      });
    }

    const newRef = db().collection(COLL_LINK_CODES).doc();
    batch.set(newRef, {
      studentId,
      schoolId,
      code,
      status: "active",
      createdAt: now,
      expiresAt,
      createdBy: uid,
      metadata,
      intendedFor: "co_parent_invite",
      note: note ?? null,
    });
    await batch.commit();

    return {
      ok: true,
      id: newRef.id,
      code,
      studentId,
      schoolId,
      expiresAt: expiresAt.toDate().toISOString(),
      metadata,
      intendedFor: "co_parent_invite",
      note: note ?? null,
    };
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
    assertNotReadOnly(context);
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
