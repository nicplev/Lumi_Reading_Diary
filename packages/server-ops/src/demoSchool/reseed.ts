import { createHash, randomUUID } from "node:crypto";
import type { Auth, UserRecord } from "firebase-admin/auth";
import type {
  DocumentReference,
  Firestore,
  Query,
  WriteResult,
} from "firebase-admin/firestore";
import type { Storage } from "firebase-admin/storage";
import type { Actor } from "../audit";
import {
  buildDemoSchoolPlan,
  demoControlDefaults,
  demoSchoolConstants,
  type DemoAuthUser,
  type DemoPlanDocument,
  type DemoSchoolPlan,
} from "./plan";

export type DemoReseedTrigger = "provision" | "manual" | "cli";

export interface DemoReseedResult {
  leaseId: string;
  schoolId: string;
  docsWritten: number;
  communityBooksDeleted: number;
  finishedAtISO: string;
}

export class DemoReseedConflictError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "DemoReseedConflictError";
  }
}

const STATUS_PATH = "demoAccess/reseedStatus";
const STALE_LEASE_MS = 10 * 60 * 1000;
const DEMO_EMAIL_RE = /^(?:[^@]+@lumidemo\.school|support\+demo(?:\.[^@]+)?@lumi-reading\.com)$/;

function hashEmail(email: string): string {
  return createHash("sha256").update(email.trim().toLowerCase()).digest("hex");
}

function asDate(value: unknown): Date | null {
  if (value instanceof Date) return value;
  if (
    value &&
    typeof value === "object" &&
    "toDate" in value &&
    typeof (value as { toDate?: unknown }).toDate === "function"
  ) {
    return (value as { toDate: () => Date }).toDate();
  }
  return null;
}

function safeError(error: unknown): string {
  const message = error instanceof Error ? error.message : "Unknown reseed failure";
  // Status is visible to operators. Avoid persisting stack traces, tokens,
  // credentials or unbounded third-party error payloads.
  return message.replace(/[\r\n]+/g, " ").slice(0, 500);
}

async function acquireLease(
  db: Firestore,
  actor: Actor,
  trigger: DemoReseedTrigger,
  schoolId: string
): Promise<string> {
  const statusRef = db.doc(STATUS_PATH);
  const leaseId = randomUUID();
  const now = new Date();

  await db.runTransaction(async (tx) => {
    const status = await tx.get(statusRef);
    const data = status.data();
    const heartbeat = asDate(data?.heartbeatAt ?? data?.startedAt);
    const freshRunning =
      data?.state === "running" &&
      heartbeat !== null &&
      now.getTime() - heartbeat.getTime() < STALE_LEASE_MS;
    if (freshRunning) {
      throw new DemoReseedConflictError("A demo reseed is already running.");
    }

    tx.set(statusRef, {
      state: "running",
      schoolId,
      leaseId,
      trigger,
      phase: "locked",
      startedAt: now,
      heartbeatAt: now,
      finishedAt: null,
      startedBy: { uid: actor.uid, email: actor.email ?? null },
      docsWritten: 0,
      communityBooksDeleted: 0,
      error: null,
    });
  });

  return leaseId;
}

async function checkpoint(
  db: Firestore,
  leaseId: string,
  phase: string,
  extra: Record<string, unknown> = {}
): Promise<void> {
  const ref = db.doc(STATUS_PATH);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data();
    if (data?.state !== "running" || data?.leaseId !== leaseId) {
      throw new DemoReseedConflictError(
        "This reseed no longer owns the active lease."
      );
    }
    tx.update(ref, { phase, heartbeatAt: new Date(), ...extra });
  });
}

async function completeLease(
  db: Firestore,
  leaseId: string,
  actor: Actor,
  trigger: DemoReseedTrigger,
  schoolId: string,
  finishedAt: Date,
  docsWritten: number,
  communityBooksDeleted: number
): Promise<void> {
  const statusRef = db.doc(STATUS_PATH);
  const controlStatusRef = db.doc("demoAccess/controlStatus");
  const auditRef = db.collection("adminAuditLog").doc();
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(statusRef);
    if (snap.data()?.state !== "running" || snap.data()?.leaseId !== leaseId) {
      throw new DemoReseedConflictError(
        "This reseed no longer owns the active lease."
      );
    }
    tx.update(statusRef, {
      phase: "complete",
      state: "succeeded",
      heartbeatAt: finishedAt,
      finishedAt,
      docsWritten,
      communityBooksDeleted,
    });
    // The school document has just been rebuilt from the canonical defaults.
    // Advance this separate status timestamp in the same completion
    // transaction so already-open super-admin panels remount instead of
    // continuing to display their pre-reseed local switch state.
    tx.set(controlStatusRef, {
      schoolId,
      controls: {
        audioRecordingEnabled: demoControlDefaults.audioRecordingEnabled,
        parentCommentsEnabled: demoControlDefaults.parentCommentsEnabled,
        freeTextCommentsEnabled: demoControlDefaults.freeTextCommentsEnabled,
        messagingEnabled: demoControlDefaults.messagingEnabled,
        quickLoggingEnabled: demoControlDefaults.quickLoggingEnabled,
        commentCategoryCount: demoControlDefaults.commentPresets.length,
        commentChipCount: demoControlDefaults.commentPresets.reduce(
          (total, preset) => total + preset.chips.length,
          0,
        ),
      },
      updatedAt: finishedAt,
      updatedBy: { uid: actor.uid, email: actor.email ?? null },
      resetByReseed: { trigger, leaseId },
    });
    tx.set(auditRef, {
      action: "demo.reseed",
      performedBy: actor.uid,
      performedByEmail: actor.email ?? null,
      targetType: "school",
      targetId: schoolId,
      schoolId,
      after: { trigger, docsWritten, communityBooksDeleted },
      metadata: { leaseId },
      createdAt: finishedAt,
    });
  });
}

async function deleteQuery(db: Firestore, query: Query): Promise<number> {
  const snap = await query.get();
  if (snap.empty) return 0;
  const writer = db.bulkWriter();
  for (const doc of snap.docs) writer.delete(doc.ref);
  await writer.close();
  return snap.size;
}

async function preflightAndEnsureAuth(
  auth: Auth,
  plan: DemoSchoolPlan
): Promise<void> {
  for (const user of plan.authUsers) {
    let byEmail: UserRecord | null = null;
    try {
      byEmail = await auth.getUserByEmail(user.email);
    } catch (error) {
      if ((error as { code?: string }).code !== "auth/user-not-found") throw error;
    }

    if (byEmail && byEmail.uid !== user.uid) {
      throw new Error(
        `Safety stop: ${user.email} belongs to an unexpected Auth uid.`
      );
    }

    let byUid: UserRecord | null = byEmail;
    if (!byUid) {
      try {
        byUid = await auth.getUser(user.uid);
      } catch (error) {
        if ((error as { code?: string }).code !== "auth/user-not-found") throw error;
      }
    }

    if (byUid) {
      const previousEmail = byUid.email ?? "";
      if (!DEMO_EMAIL_RE.test(previousEmail)) {
        throw new Error(
          `Safety stop: deterministic demo uid ${user.uid} has a non-demo email.`
        );
      }
      await auth.updateUser(user.uid, {
        email: user.email,
        displayName: user.fullName,
        emailVerified: true,
        multiFactor: { enrolledFactors: [] },
      });
    } else {
      // Do not mint or rotate a password here. The daily provision operation is
      // the only code path allowed to issue the shared credential.
      await auth.createUser({
        uid: user.uid,
        email: user.email,
        displayName: user.fullName,
        emailVerified: true,
      });
    }
  }
}

async function cleanupExternalData(
  db: Firestore,
  storage: Storage,
  plan: DemoSchoolPlan
): Promise<number> {
  const { schoolId, retiredIndexEmails } = demoSchoolConstants;
  await deleteQuery(
    db,
    db.collection("studentLinkCodes").where("schoolId", "==", schoolId)
  );

  const writer = db.bulkWriter();
  for (const entry of plan.indexEntries) {
    writer.delete(db.collection("userSchoolIndex").doc(entry.id));
  }
  for (const email of retiredIndexEmails) {
    writer.delete(db.collection("userSchoolIndex").doc(hashEmail(email)));
  }
  for (const user of plan.users) {
    writer.delete(db.collection("users").doc(user.id));
  }
  await writer.close();

  const contributorIds = plan.authUsers.map((user) => user.uid);
  let communityBooksDeleted = 0;
  for (let offset = 0; offset < contributorIds.length; offset += 30) {
    const ids = contributorIds.slice(offset, offset + 30);
    const snap = await db
      .collection("community_books")
      .where("contributedBy", "in", ids)
      .get();
    if (snap.empty) continue;

    const communityWriter = db.bulkWriter();
    for (const doc of snap.docs) {
      const data = doc.data();
      const isbn = String(data.isbnNormalized ?? data.isbn ?? doc.id)
        .replace(/^isbn_/, "")
        .trim();
      if (/^(?:\d{10}|\d{13})$/.test(isbn)) {
        await storage
          .bucket()
          .file(`community_books/covers/${isbn}.jpg`)
          .delete({ ignoreNotFound: true });
      }
      communityWriter.delete(doc.ref);
      communityBooksDeleted += 1;
    }
    await communityWriter.close();
  }

  return communityBooksDeleted;
}

async function writeDocuments(
  db: Firestore,
  docs: Array<{ ref: DocumentReference; value: Record<string, any> }>
): Promise<number> {
  const writer = db.bulkWriter();
  let failed: Error | null = null;
  writer.onWriteError((error) => {
    if (error.failedAttempts < 3) return true;
    failed = error;
    return false;
  });
  const writes: Array<Promise<WriteResult>> = [];
  for (const doc of docs) writes.push(writer.set(doc.ref, doc.value));
  await writer.close();
  await Promise.all(writes);
  if (failed) throw failed;
  return docs.length;
}

function schoolDocs(
  db: Firestore,
  plan: DemoSchoolPlan
): Array<{ ref: DocumentReference; value: Record<string, any> }> {
  const schoolRef = db.collection("schools").doc(plan.school.id);
  const docs = [{ ref: schoolRef, value: plan.school.data }];
  const append = (collection: string, items: DemoPlanDocument[]) => {
    for (const item of items) {
      docs.push({ ref: schoolRef.collection(collection).doc(item.id), value: item.data });
    }
  };
  append("users", plan.users);
  append("parents", plan.parents);
  append("classes", plan.classes);
  append("students", plan.students);
  append("books", plan.books);
  append("allocations", plan.allocations);
  return docs;
}

async function seedPlan(db: Firestore, plan: DemoSchoolPlan): Promise<number> {
  let count = 0;
  const schoolRef = db.collection("schools").doc(plan.school.id);

  // The production validation triggers read students and parent links on log
  // create, so dependency documents must be committed first. The reseed causes
  // the same bounded trigger fan-out as the historical manual reset.
  count += await writeDocuments(db, schoolDocs(db, plan));

  count += await writeDocuments(
    db,
    plan.logs.map((item) => ({
      ref: schoolRef.collection("readingLogs").doc(item.id),
      value: item.data,
    }))
  );

  count += await writeDocuments(db, [
    ...plan.comments.map((item) => ({
      ref: schoolRef
        .collection("readingLogs")
        .doc(item.logId)
        .collection("comments")
        .doc(item.id),
      value: item.data,
    })),
    ...plan.linkCodes.map((item) => ({
      ref: db.collection("studentLinkCodes").doc(item.id),
      value: item.data,
    })),
    ...plan.indexEntries.map((item) => ({
      ref: db.collection("userSchoolIndex").doc(item.id),
      value: item.data,
    })),
    ...plan.users.map((item) => ({
      ref: db.collection("users").doc(item.id),
      value: item.data,
    })),
  ]);

  const configRef = db.doc("platformConfig/demoAccess");
  const configSnap = await configRef.get();
  const existing = configSnap.data() ?? {};
  const shared = Object.fromEntries(plan.authUsers.map((user) => [user.key, user.email]));
  await configRef.set({
    schoolId: demoSchoolConstants.schoolId,
    adminEmail: shared.sharedadmin,
    teacherEmail: shared.teacher,
    parentEmail: shared.parent1,
    scrambleOnlyEmails: plan.authUsers
      .filter((user) => !["sharedadmin", "teacher", "parent1"].includes(user.key))
      .map((user) => user.email),
    portalLoginUrl: "https://lumi-school-admin-au.web.app/login",
    marketingUrl: "https://lumi-reading.com",
    appStoreUrl: existing.appStoreUrl ?? null,
    playStoreUrl: existing.playStoreUrl ?? null,
    updatedAt: new Date(),
    updatedBy: "demo_reseed",
  });
  count += 1;

  return count;
}

function exactClaims(user: DemoAuthUser): Record<string, unknown> {
  const claims: Record<string, unknown> = {
    demoAccount: true,
    demoSchoolId: demoSchoolConstants.schoolId,
    schoolId: demoSchoolConstants.schoolId,
  };
  if (user.key === "sharedadmin") {
    claims.demoAdminMfaExempt = true;
    claims.demoReadOnly = true;
  }
  return claims;
}

async function finaliseClaims(auth: Auth, plan: DemoSchoolPlan): Promise<void> {
  for (const user of plan.authUsers) {
    await auth.setCustomUserClaims(user.uid, exactClaims(user));
    // Force stale broad/read-only token shapes out after the successful seed.
    await auth.revokeRefreshTokens(user.uid);
  }
}

/**
 * Destructively refresh the one immutable demo tenant. The top-level status
 * document is a fencing lease: all demo-interactive Rules require succeeded,
 * and every destructive phase re-checks ownership before continuing.
 */
export async function reseedDemoSchool(
  auth: Auth,
  db: Firestore,
  storage: Storage,
  actor: Actor,
  options: { trigger: DemoReseedTrigger; now?: Date }
): Promise<DemoReseedResult> {
  const plan = buildDemoSchoolPlan(options.now ?? new Date());
  const { schoolId } = demoSchoolConstants;
  const schoolRef = db.collection("schools").doc(schoolId);
  const school = await schoolRef.get();
  if (!school.exists || school.data()?.isDemo !== true) {
    throw new Error(
      `Safety stop: ${schoolId} is missing or is not authoritatively marked isDemo:true.`
    );
  }

  const leaseId = await acquireLease(db, actor, options.trigger, schoolId);
  let docsWritten = 0;
  let communityBooksDeleted = 0;

  try {
    await checkpoint(db, leaseId, "auth-preflight");
    await preflightAndEnsureAuth(auth, plan);

    await checkpoint(db, leaseId, "external-cleanup");
    communityBooksDeleted = await cleanupExternalData(db, storage, plan);

    await checkpoint(db, leaseId, "school-delete", {
      communityBooksDeleted,
    });
    const freshGuard = await schoolRef.get();
    if (!freshGuard.exists || freshGuard.data()?.isDemo !== true) {
      throw new Error("Safety stop: demo marker changed before recursive delete.");
    }
    await db.recursiveDelete(schoolRef);

    await checkpoint(db, leaseId, "firestore-seed", {
      communityBooksDeleted,
    });
    docsWritten = await seedPlan(db, plan);

    await checkpoint(db, leaseId, "claims-finalise", {
      docsWritten,
      communityBooksDeleted,
    });
    await finaliseClaims(auth, plan);

    const finishedAt = new Date();
    await completeLease(
      db,
      leaseId,
      actor,
      options.trigger,
      schoolId,
      finishedAt,
      docsWritten,
      communityBooksDeleted
    );

    return {
      leaseId,
      schoolId,
      docsWritten,
      communityBooksDeleted,
      finishedAtISO: finishedAt.toISOString(),
    };
  } catch (error) {
    const ref = db.doc(STATUS_PATH);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (snap.data()?.leaseId === leaseId) {
        tx.update(ref, {
          state: "failed",
          phase: "failed",
          finishedAt: new Date(),
          heartbeatAt: new Date(),
          docsWritten,
          communityBooksDeleted,
          error: safeError(error),
        });
      }
    }).catch(() => undefined);
    throw error;
  }
}
