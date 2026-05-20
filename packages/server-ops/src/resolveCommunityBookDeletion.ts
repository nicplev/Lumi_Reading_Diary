import type { Firestore } from "firebase-admin/firestore";
import type { Storage } from "firebase-admin/storage";
import { z } from "zod";
import { logAuditEvent, ServerOpsValidationError, type Actor } from "./audit";

const paramsSchema = z.object({
  isbn: z.string().min(1, "ISBN is required"),
  requestId: z.string().min(1, "requestId is required"),
  action: z.enum(["approved", "rejected"]),
});

export interface ResolveCommunityBookDeletionParams {
  isbn: string;
  requestId: string;
  action: "approved" | "rejected";
}

export interface ResolveCommunityBookDeletionResult {
  success: true;
  action: "approved" | "rejected";
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

  const requestRef = db
    .collection("community_books").doc(isbn)
    .collection("deletionRequests").doc(requestId);

  const requestDoc = await requestRef.get();
  if (!requestDoc.exists) {
    throw new ServerOpsValidationError("Deletion request not found");
  }
  if (requestDoc.data()?.status !== "pending") {
    throw new ServerOpsValidationError("Request has already been resolved");
  }

  if (action === "approved") {
    const batch = db.batch();
    batch.update(requestRef, {
      status: "approved",
      resolvedAt: new Date(),
      resolvedBy: actor.uid,
    });
    batch.delete(db.collection("community_books").doc(isbn));
    await batch.commit();

    // School-library copies — best-effort, outside the batch since the count
    // is unbounded and may exceed the 500-write limit.
    const schoolsSnap = await db.collection("schools").get();
    await Promise.all(
      schoolsSnap.docs.map(async (schoolDoc) => {
        const bookCopy = db
          .collection("schools").doc(schoolDoc.id)
          .collection("books").doc(`isbn_${isbn}`);
        const copyDoc = await bookCopy.get();
        if (copyDoc.exists) {
          await bookCopy.delete();
        }
      })
    );

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
    metadata: { requestId, action },
  }).catch((e) => {
    console.error(
      "[server-ops] audit log failed for community_book_deletion",
      e
    );
  });

  return { success: true, action };
}
