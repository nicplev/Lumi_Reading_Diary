import type { Firestore } from "firebase-admin/firestore";
import type { Storage } from "firebase-admin/storage";
import { z } from "zod";
import { logAuditEvent, ServerOpsValidationError, type Actor } from "./audit";
import { cascadeBookRemovalForSchool, normalizeIsbn } from "./allocationCascade";
import { mapSettledWithLimit } from "./utils/concurrency";

const paramsSchema = z.object({
  isbn: z.string().min(1, "ISBN is required"),
  requestId: z.string().min(1, "requestId is required"),
  action: z.enum(["approved", "rejected"]),
});

// How many schools are swept at once. Each sweep holds one school's
// allocations in memory; 5 keeps the peak well inside the 512MiB backend
// while still overlapping the Firestore round-trips.
const SCHOOL_SWEEP_CONCURRENCY = 5;

export interface ResolveCommunityBookDeletionParams {
  isbn: string;
  requestId: string;
  action: "approved" | "rejected";
}

export interface ResolveCommunityBookDeletionResult {
  success: true;
  action: "approved" | "rejected";
  /**
   * False when one or more schools failed their allocation sweep. The book is
   * still deleted, but some students may retain assignments for it — the
   * request stays resumable and re-approving retries the sweep.
   */
  cascadeComplete?: boolean;
  /** Schools whose sweep threw, when cascadeComplete is false. */
  cascadeFailedSchools?: number;
  allocationsUpdated?: number;
}

// Resolving a deletion request: on "approved" this deletes the community book
// document, every school-library copy, and the cover image; on "rejected" it
// only stamps the request. Storage is passed explicitly so the module stays
// decoupled from any one app's firebase-admin singleton.
export async function resolveCommunityBookDeletion(
  db: Firestore,
  storage: Storage,
  actor: Actor,
  params: ResolveCommunityBookDeletionParams
): Promise<ResolveCommunityBookDeletionResult> {
  const parsed = paramsSchema.safeParse(params);
  if (!parsed.success) {
    throw new ServerOpsValidationError(
      parsed.error.issues.map((e) => e.message).join(", ")
    );
  }
  const { isbn, requestId, action } = parsed.data;
  // Item matching is case-normalized (ISBNs may carry a trailing "X").
  const normalizedIsbn = normalizeIsbn(isbn);
  if (!normalizedIsbn) {
    throw new ServerOpsValidationError("ISBN is required");
  }

  const requestRef = db
    .collection("community_books").doc(isbn)
    .collection("deletionRequests").doc(requestId);

  const requestDoc = await requestRef.get();
  if (!requestDoc.exists) {
    throw new ServerOpsValidationError("Deletion request not found");
  }
  let sweepOutcome: {
    cascadeComplete: boolean;
    cascadeFailedSchools: number;
    allocationsUpdated: number;
  } | null = null;

  const requestData = requestDoc.data() ?? {};
  const status = requestData.status;
  // An approved request whose sweep never finished is resumable: re-approving
  // it retries the fan-out. Without this, a container that died mid-sweep
  // would leave the book deleted but some schools still holding assignments,
  // with no way to finish the job. Every step below is idempotent, so a repeat
  // run is safe.
  const resumingIncompleteSweep =
    status === "approved" &&
    action === "approved" &&
    !requestData.cascadeCompletedAt;
  if (status !== "pending" && !resumingIncompleteSweep) {
    throw new ServerOpsValidationError("Request has already been resolved");
  }

  if (action === "approved") {
    const batch = db.batch();
    batch.update(requestRef, {
      status: "approved",
      resolvedAt: requestData.resolvedAt ?? new Date(),
      resolvedBy: requestData.resolvedBy ?? actor.uid,
    });
    batch.delete(db.collection("community_books").doc(isbn));
    await batch.commit();

    // School-library copies — best-effort, outside the batch since the count
    // is unbounded and may exceed the 500-write limit.
    const schoolsSnap = await db.collection("schools").get();
    const stamp = {
      removedAt: new Date(),
      removedBy: actor.uid,
      reason: "community_book_deleted",
    };

    // Bounded fan-out. Each school's sweep loads that school's allocations
    // into memory; the portal runs on a 512MiB frameworksBackend, so an
    // unbounded Promise.all over every school can exhaust the container long
    // before the request times out.
    const results = await mapSettledWithLimit(
      schoolsSnap.docs,
      SCHOOL_SWEEP_CONCURRENCY,
      async (schoolDoc) => {
        const bookCopy = db
          .collection("schools").doc(schoolDoc.id)
          .collection("books").doc(`isbn_${isbn}`);
        const copyDoc = await bookCopy.get();
        if (copyDoc.exists) {
          await bookCopy.delete();
        }

        // Retire the book from this school's allocations. Without this the
        // book document is gone but students keep an assignment pointing at
        // it, which surfaces as a title with no library entry.
        return cascadeBookRemovalForSchool(
          db,
          schoolDoc.id,
          { isbn: normalizedIsbn, bookId: `isbn_${isbn}` },
          stamp
        );
      }
    );

    // One school failing must not abort the rest, but it must not be silent
    // either: leave cascadeCompletedAt unset so the request stays resumable
    // and surface the count to the caller.
    const failures = results.filter((r) => r.status === "rejected");
    for (const failure of failures) {
      console.error(
        "[server-ops] allocation sweep failed for a school",
        (failure as PromiseRejectedResult).reason
      );
    }
    const allocationsUpdated = results.reduce(
      (sum, r) => sum + (r.status === "fulfilled" ? r.value : 0),
      0
    );

    if (failures.length === 0) {
      await requestRef.update({
        cascadeCompletedAt: new Date(),
        cascadeSchoolsSwept: schoolsSnap.size,
        cascadeAllocationsUpdated: allocationsUpdated,
      });
    }
    sweepOutcome = {
      cascadeComplete: failures.length === 0,
      cascadeFailedSchools: failures.length,
      allocationsUpdated,
    };

    // Cover image — best-effort; it may legitimately not exist.
    try {
      await storage.bucket().file(`community_books/covers/${isbn}.jpg`).delete();
    } catch {
      // not critical
    }
  } else {
    await requestRef.update({
      status: "rejected",
      resolvedAt: new Date(),
      resolvedBy: actor.uid,
    });
  }

  await logAuditEvent(db, {
    action: `community_book_deletion_${action}`,
    performedBy: actor.uid,
    performedByEmail: actor.email,
    targetType: "community_book",
    targetId: isbn,
    metadata: { requestId, action, resumed: resumingIncompleteSweep, ...(sweepOutcome ?? {}) },
  }).catch((e) => {
    console.error(
      "[server-ops] audit log failed for community_book_deletion",
      e
    );
  });

  return { success: true, action, ...(sweepOutcome ?? {}) };
}
