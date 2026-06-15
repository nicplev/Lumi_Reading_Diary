/**
 * Library counts denormalization.
 *
 * The teacher-facing library screen surfaces header badges ("X books, Y
 * decodable, Z library, W hidden") that previously required reading the
 * entire `schools/{schoolId}/books` collection to compute. Paginating the
 * collection (PR3) breaks that — loaded pages aren't the same as the
 * whole library.
 *
 * This trigger maintains a small denormalized doc at
 * `schools/{schoolId}/libraryMeta/counts` so the client can show accurate
 * badges with a single doc read instead of a 5000-doc collection read.
 * Self-heals on first write per school by full-scanning the books
 * collection once. After that, incremental deltas keep it accurate.
 *
 * Hidden books are local to each teacher (SharedPreferences) so they
 * cannot be denormalized here — the client still applies that filter
 * client-side over loaded pages.
 */

import * as admin from "firebase-admin";
import * as functions from "firebase-functions";

const fns = functions.region("australia-southeast1");

const UNRECOGNISED_BOOK_TITLE = "Unrecognised Book";

/**
 * Mirror of `SchoolLibraryService.isDecodable` from the Flutter client.
 * Must stay in lock-step with that definition.
 * @param {FirebaseFirestore.DocumentData | undefined} data Book doc data.
 * @return {boolean} Whether this book is treated as decodable.
 */
function isDecodable(data: FirebaseFirestore.DocumentData | undefined): boolean {
  if (!data) return false;
  const meta = data.metadata;
  if (!meta) return false;
  if (typeof meta.llllProductCode === "string" && meta.llllProductCode.length > 0) {
    return true;
  }
  return meta.isDecodable === true;
}

/**
 * Mirror of `SchoolLibraryService._isDisplayable`. Books we wouldn't show
 * to teachers shouldn't count toward header badges either.
 * @param {FirebaseFirestore.DocumentData | undefined} data Book doc data.
 * @return {boolean} Whether this book is displayed in the library UI.
 */
function isDisplayable(
  data: FirebaseFirestore.DocumentData | undefined,
): boolean {
  if (!data) return false;
  if (data.metadata?.placeholder === true) return false;
  const title = typeof data.title === "string" ? data.title : "";
  if (title.length === 0) return false;
  if (title === UNRECOGNISED_BOOK_TITLE) return false;
  return true;
}

/**
 * Full-scan + write the counts doc. Used as the self-heal seed the very
 * first time a write happens for a school whose counts doc isn't present
 * yet (e.g. an existing school after this PR ships, before any new book
 * is added). Idempotent on best-effort — a rare race between two seed
 * runs could under- or over-count by 1; the weekly stats reconciler
 * could be extended to also reseed counts if drift is observed.
 * @param {string} schoolId The school document ID.
 * @return {Promise<void>} Resolves when the counts doc has been written.
 */
async function seedLibraryCounts(schoolId: string): Promise<void> {
  const db = admin.firestore();
  const booksSnap = await db
    .collection(`schools/${schoolId}/books`)
    .get();

  let total = 0;
  let decodable = 0;
  booksSnap.docs.forEach((doc) => {
    const data = doc.data();
    if (!isDisplayable(data)) return;
    total++;
    if (isDecodable(data)) decodable++;
  });

  await db
    .collection("schools").doc(schoolId)
    .collection("libraryMeta").doc("counts")
    .set({
      total,
      decodable,
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    });
}

export const maintainLibraryCounts = fns.firestore
  .document("schools/{schoolId}/books/{bookId}")
  .onWrite(async (change, context) => {
    const schoolId = context.params.schoolId;
    const db = admin.firestore();
    const countsRef = db
      .collection("schools").doc(schoolId)
      .collection("libraryMeta").doc("counts");

    const beforeData = change.before.exists ? change.before.data() : undefined;
    const afterData = change.after.exists ? change.after.data() : undefined;

    const beforeDisplayable = isDisplayable(beforeData);
    const afterDisplayable = isDisplayable(afterData);
    const beforeDecodable = beforeDisplayable && isDecodable(beforeData);
    const afterDecodable = afterDisplayable && isDecodable(afterData);

    let deltaTotal = 0;
    if (!beforeDisplayable && afterDisplayable) deltaTotal = 1;
    else if (beforeDisplayable && !afterDisplayable) deltaTotal = -1;

    let deltaDecodable = 0;
    if (!beforeDecodable && afterDecodable) deltaDecodable = 1;
    else if (beforeDecodable && !afterDecodable) deltaDecodable = -1;

    if (deltaTotal === 0 && deltaDecodable === 0) return null;

    // Self-heal: if the counts doc doesn't exist yet, seed it via a full
    // scan that already includes this write's after-state, and return
    // without incrementing — the seed counted it.
    const countsSnap = await countsRef.get();
    if (!countsSnap.exists) {
      try {
        await seedLibraryCounts(schoolId);
      } catch (err) {
        functions.logger.error("seedLibraryCounts failed", {
          schoolId,
          error: err instanceof Error ? err.message : String(err),
        });
      }
      return null;
    }

    try {
      await countsRef.update({
        total: admin.firestore.FieldValue.increment(deltaTotal),
        decodable: admin.firestore.FieldValue.increment(deltaDecodable),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (err) {
      functions.logger.error("maintainLibraryCounts update failed", {
        schoolId,
        bookId: context.params.bookId,
        error: err instanceof Error ? err.message : String(err),
      });
      throw err;
    }
    return null;
  });
