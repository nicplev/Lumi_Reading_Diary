import test, { after, before, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { deleteApp, getApps, initializeApp, type App } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import type { Storage } from "firebase-admin/storage";
import { resolveCommunityBookDeletion } from "../src/resolveCommunityBookDeletion";

// End-to-end cover for the community-book deletion sweep against a real
// Firestore emulator. The pure matching logic is unit-tested in
// communityBookDeletionCascade.test.ts; what this file exercises is the
// orchestration around it — that the book really disappears, that allocations
// really get retired, that the completion marker is only written on a clean
// sweep, and that an interrupted sweep can be resumed.

const PROJECT_ID = "demo-lumi-community-book-deletion";
const ISBN = "9780141354828";
const REQUEST_ID = "req1";
const ACTOR = { uid: "super-admin-1", email: "admin@example.test" };

let app: App;
let deletedObjects: string[] = [];

const storage = {
  bucket: () => ({
    file: (path: string) => ({
      delete: async () => {
        deletedObjects.push(path);
      },
    }),
  }),
} as unknown as Storage;

before(() => {
  app = initializeApp({ projectId: PROJECT_ID }, "community-book-deletion-test");
});

after(async () => {
  if (getApps().includes(app)) await deleteApp(app);
});

beforeEach(async () => {
  const db = getFirestore(app);
  for (const collection of ["adminAuditLog", "community_books", "schools"]) {
    await db.recursiveDelete(db.collection(collection));
  }
  deletedObjects = [];
});

/**
 * Seeds a pending deletion request plus `schoolCount` schools, each holding a
 * library copy of the book and one allocation that assigns it alongside an
 * unrelated title.
 */
async function seed(
  db: Firestore,
  schoolCount: number,
  requestOverrides: Record<string, unknown> = {}
): Promise<string[]> {
  await db.collection("community_books").doc(ISBN).set({
    title: "Matilda",
    isbn: ISBN,
  });
  await db
    .collection("community_books").doc(ISBN)
    .collection("deletionRequests").doc(REQUEST_ID)
    .set({ status: "pending", reason: "duplicate", ...requestOverrides });

  const schoolIds: string[] = [];
  for (let i = 0; i < schoolCount; i++) {
    const schoolId = `school${i}`;
    schoolIds.push(schoolId);
    await db.collection("schools").doc(schoolId).set({ name: `School ${i}` });
    await db
      .collection("schools").doc(schoolId)
      .collection("books").doc(`isbn_${ISBN}`)
      .set({ title: "Matilda", isbn: ISBN });
    await db
      .collection("schools").doc(schoolId)
      .collection("allocations").doc("alloc1")
      .set({
        classId: "classA",
        studentIds: ["stu1"],
        // Realistic shape: items carry both the ISBN and the library bookId,
        // and the legacy bookTitles/bookIds arrays mirror them.
        assignmentItems: [
          {
            id: "a",
            title: "Matilda",
            isbn: ISBN,
            bookId: `isbn_${ISBN}`,
            isDeleted: false,
          },
          {
            id: "b",
            title: "The BFG",
            isbn: "9780141365404",
            bookId: "isbn_9780141365404",
            isDeleted: false,
          },
        ],
        bookTitles: ["Matilda", "The BFG"],
        bookIds: [`isbn_${ISBN}`, "isbn_9780141365404"],
      });
  }
  return schoolIds;
}

async function readAllocation(db: Firestore, schoolId: string) {
  const doc = await db
    .collection("schools").doc(schoolId)
    .collection("allocations").doc("alloc1")
    .get();
  return doc.data() as Record<string, unknown>;
}

async function readRequest(db: Firestore) {
  const doc = await db
    .collection("community_books").doc(ISBN)
    .collection("deletionRequests").doc(REQUEST_ID)
    .get();
  return doc.data() as Record<string, unknown>;
}

/**
 * Wraps `db` so that one school's allocations query throws, simulating a
 * mid-sweep failure without needing to kill the process.
 */
function withFailingSchoolAllocations(
  realDb: Firestore,
  poisonSchoolId: string
): Firestore {
  const bind = (target: object, prop: string | symbol) => {
    const value = Reflect.get(target, prop);
    return typeof value === "function" ? value.bind(target) : value;
  };

  return new Proxy(realDb, {
    get(target, prop) {
      if (prop !== "collection") return bind(target, prop);
      return (name: string) => {
        const collection = target.collection(name);
        if (name !== "schools") return collection;
        return new Proxy(collection, {
          get(colTarget, colProp) {
            if (colProp !== "doc") return bind(colTarget, colProp);
            return (id: string) => {
              const docRef = colTarget.doc(id);
              if (id !== poisonSchoolId) return docRef;
              return new Proxy(docRef, {
                get(docTarget, docProp) {
                  if (docProp !== "collection") return bind(docTarget, docProp);
                  return (sub: string) => {
                    if (sub !== "allocations") return docTarget.collection(sub);
                    return {
                      get: async () => {
                        throw new Error("injected allocations failure");
                      },
                    };
                  };
                },
              });
            };
          },
        });
      };
    },
  }) as Firestore;
}

test("approval deletes the book and retires it from every school's allocations", async () => {
  const db = getFirestore(app);
  const schoolIds = await seed(db, 3);

  const result = await resolveCommunityBookDeletion(db, storage, ACTOR, {
    isbn: ISBN,
    requestId: REQUEST_ID,
    action: "approved",
  });

  assert.equal(result.success, true);
  assert.equal(result.cascadeComplete, true);
  assert.equal(result.allocationsUpdated, 3);

  // Community book document is gone.
  const communityBook = await db.collection("community_books").doc(ISBN).get();
  assert.equal(communityBook.exists, false);

  // Cover image deletion was attempted.
  assert.deepEqual(deletedObjects, [`community_books/covers/${ISBN}.jpg`]);

  for (const schoolId of schoolIds) {
    // School library copy is gone.
    const copy = await db
      .collection("schools").doc(schoolId)
      .collection("books").doc(`isbn_${ISBN}`)
      .get();
    assert.equal(copy.exists, false, `book copy survived in ${schoolId}`);

    // The assignment is retired, the unrelated title untouched.
    const allocation = await readAllocation(db, schoolId);
    const items = allocation.assignmentItems as Record<string, unknown>[];
    assert.equal(items[0].isDeleted, true, `not retired in ${schoolId}`);
    assert.equal(items[1].isDeleted, false);
    assert.deepEqual(allocation.bookTitles, ["The BFG"]);
    assert.deepEqual(allocation.bookIds, ["isbn_9780141365404"]);
  }

  // Completion marker written.
  const request = await readRequest(db);
  assert.equal(request.status, "approved");
  assert.ok(request.cascadeCompletedAt, "cascadeCompletedAt was not set");
  assert.equal(request.cascadeSchoolsSwept, 3);
  assert.equal(request.cascadeAllocationsUpdated, 3);
});

test("a school failing mid-sweep leaves the request resumable", async () => {
  const db = getFirestore(app);
  await seed(db, 3);

  const result = await resolveCommunityBookDeletion(
    withFailingSchoolAllocations(db, "school1"),
    storage,
    ACTOR,
    { isbn: ISBN, requestId: REQUEST_ID, action: "approved" }
  );

  // The caller is told the sweep was incomplete rather than a clean success.
  assert.equal(result.cascadeComplete, false);
  assert.equal(result.cascadeFailedSchools, 1);

  // Healthy schools were still swept — one failure does not sink the rest.
  const healthy = await readAllocation(db, "school0");
  assert.equal(
    (healthy.assignmentItems as Record<string, unknown>[])[0].isDeleted,
    true
  );

  // The poisoned school still holds the assignment.
  const stranded = await readAllocation(db, "school1");
  assert.equal(
    (stranded.assignmentItems as Record<string, unknown>[])[0].isDeleted,
    false
  );

  // No completion marker, so the request stays resumable.
  const request = await readRequest(db);
  assert.equal(request.status, "approved");
  assert.equal(request.cascadeCompletedAt, undefined);
});

test("re-approving an interrupted request finishes the sweep", async () => {
  const db = getFirestore(app);
  await seed(db, 3);

  // First pass fails on school1.
  await resolveCommunityBookDeletion(
    withFailingSchoolAllocations(db, "school1"),
    storage,
    ACTOR,
    { isbn: ISBN, requestId: REQUEST_ID, action: "approved" }
  );
  const strandedBefore = await readAllocation(db, "school1");
  assert.equal(
    (strandedBefore.assignmentItems as Record<string, unknown>[])[0].isDeleted,
    false
  );

  // Second pass, healthy db: the resume branch must accept an already-approved
  // request whose sweep never completed.
  const retry = await resolveCommunityBookDeletion(db, storage, ACTOR, {
    isbn: ISBN,
    requestId: REQUEST_ID,
    action: "approved",
  });

  assert.equal(retry.cascadeComplete, true);

  const strandedAfter = await readAllocation(db, "school1");
  assert.equal(
    (strandedAfter.assignmentItems as Record<string, unknown>[])[0].isDeleted,
    true,
    "resume did not retire the stranded assignment"
  );

  const request = await readRequest(db);
  assert.ok(request.cascadeCompletedAt, "marker not set after resume");
});

test("re-running a completed sweep is refused", async () => {
  const db = getFirestore(app);
  await seed(db, 1);

  await resolveCommunityBookDeletion(db, storage, ACTOR, {
    isbn: ISBN,
    requestId: REQUEST_ID,
    action: "approved",
  });

  await assert.rejects(
    resolveCommunityBookDeletion(db, storage, ACTOR, {
      isbn: ISBN,
      requestId: REQUEST_ID,
      action: "approved",
    }),
    /already been resolved/
  );
});

test("re-running the sweep is idempotent and preserves the original resolver", async () => {
  const db = getFirestore(app);
  await seed(db, 2);

  await resolveCommunityBookDeletion(
    withFailingSchoolAllocations(db, "school1"),
    storage,
    ACTOR,
    { isbn: ISBN, requestId: REQUEST_ID, action: "approved" }
  );
  const firstResolvedAt = (await readRequest(db)).resolvedAt;

  const secondActor = { uid: "super-admin-2", email: "other@example.test" };
  await resolveCommunityBookDeletion(db, storage, secondActor, {
    isbn: ISBN,
    requestId: REQUEST_ID,
    action: "approved",
  });

  const request = await readRequest(db);
  // The original approver and timestamp survive the retry.
  assert.equal(request.resolvedBy, ACTOR.uid);
  assert.deepEqual(request.resolvedAt, firstResolvedAt);

  // The already-retired school was not double-stamped into a broken state.
  const alreadySwept = await readAllocation(db, "school0");
  const items = alreadySwept.assignmentItems as Record<string, unknown>[];
  assert.equal(items.length, 2);
  assert.equal(items[0].isDeleted, true);
  assert.equal(items[1].isDeleted, false);
});

test("rejection stamps the request and touches nothing else", async () => {
  const db = getFirestore(app);
  await seed(db, 2);

  const result = await resolveCommunityBookDeletion(db, storage, ACTOR, {
    isbn: ISBN,
    requestId: REQUEST_ID,
    action: "rejected",
  });

  assert.equal(result.action, "rejected");
  assert.equal(result.cascadeComplete, undefined);

  // Book, copies and allocations all survive.
  const communityBook = await db.collection("community_books").doc(ISBN).get();
  assert.equal(communityBook.exists, true);
  assert.deepEqual(deletedObjects, []);

  const allocation = await readAllocation(db, "school0");
  assert.equal(
    (allocation.assignmentItems as Record<string, unknown>[])[0].isDeleted,
    false
  );

  const request = await readRequest(db);
  assert.equal(request.status, "rejected");
  assert.equal(request.cascadeCompletedAt, undefined);
});
