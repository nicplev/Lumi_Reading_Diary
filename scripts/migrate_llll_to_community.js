#!/usr/bin/env node
/**
 * One-time migration script: Seed the `community_books` Firestore collection
 * with books from the bundled LLLL (Little Learners Love Literacy) database.
 *
 * Only books with a valid ISBN are migrated (community_books is keyed by ISBN-13).
 *
 * Prerequisites:
 *   - Firebase Admin SDK credentials (either GOOGLE_APPLICATION_CREDENTIALS env var
 *     or the service-account.json from the school-admin-web project)
 *   - Node.js 18+
 *
 * Usage:
 *   # From the project root:
 *   GOOGLE_APPLICATION_CREDENTIALS=./path/to/service-account.json node scripts/migrate_llll_to_community.js
 *
 *   # Dry run (no writes):
 *   GOOGLE_APPLICATION_CREDENTIALS=./path/to/service-account.json node scripts/migrate_llll_to_community.js --dry-run
 */

const fs = require("fs");
const path = require("path");

// Firebase Admin SDK — use the one installed in functions/
const admin = require(path.join(
  __dirname,
  "..",
  "functions",
  "node_modules",
  "firebase-admin"
));

const DRY_RUN = process.argv.includes("--dry-run");

async function main() {
  // Initialize Firebase Admin.
  admin.initializeApp({
    projectId: "lumi-kakakids",
  });
  const db = admin.firestore();

  // Load the LLLL database JSON.
  const llllPath = path.join(
    __dirname,
    "..",
    "assets",
    "data",
    "llll_books_db.json"
  );
  const llllData = JSON.parse(fs.readFileSync(llllPath, "utf-8"));
  const books = llllData.books;
  const productCodes = Object.keys(books);

  console.log(`Loaded ${productCodes.length} LLLL products.`);

  // Track stats.
  let migrated = 0;
  let skippedNoIsbn = 0;
  let skippedDuplicate = 0;
  const seenIsbns = new Set();

  // Use batched writes (max 500 per batch).
  let batch = db.batch();
  let batchCount = 0;

  for (const code of productCodes) {
    const book = books[code];

    // Skip books without ISBN — we can't key them in community_books.
    if (!book.isbn) {
      skippedNoIsbn++;
      continue;
    }

    // Normalize ISBN: strip non-digit chars.
    const isbn = book.isbn.replace(/[^0-9]/g, "");
    if (isbn.length !== 13 && isbn.length !== 10) {
      console.warn(`  Skipping ${code}: invalid ISBN length (${book.isbn})`);
      skippedNoIsbn++;
      continue;
    }

    // Deduplicate: some ISBNs map to multiple product codes (state variants).
    if (seenIsbns.has(isbn)) {
      skippedDuplicate++;
      continue;
    }
    seenIsbns.add(isbn);

    const now = admin.firestore.Timestamp.now();
    const docData = {
      title: book.title || "",
      titleNormalized: (book.title || "").toLowerCase().trim(),
      author: null,
      isbn: isbn,
      coverImageUrl: book.coverImageUrl || null,
      coverStoragePath: null,
      description: null,
      genres: [],
      readingLevel: book.readingStage || null,
      pageCount: null,
      publisher: book.brand || "Little Learners Love Literacy",
      tags: book.series ? [book.series] : [],
      source: "llll_migration",
      contributedBy: "system",
      contributedBySchoolId: "system",
      contributedByName: "LLLL Database Migration",
      createdAt: now,
      updatedAt: now,
      metadata: {
        llllProductCode: book.productCode,
        llllSeries: book.series || null,
        llllProductType: book.productType || null,
        coverSource: book.coverImageUrl ? "llll_shopify" : null,
        hasCameraScannedCover: false,
      },
    };

    if (DRY_RUN) {
      console.log(`  [DRY RUN] Would write: community_books/${isbn}`);
      console.log(`    Title: ${docData.title}`);
      console.log(`    Reading Level: ${docData.readingLevel}`);
    } else {
      const docRef = db.collection("community_books").doc(isbn);
      // Use set with merge so re-running is safe (idempotent).
      batch.set(docRef, docData, { merge: true });
      batchCount++;

      // Firestore batches max at 500 operations.
      if (batchCount >= 500) {
        await batch.commit();
        console.log(`  Committed batch of ${batchCount} documents.`);
        batch = db.batch();
        batchCount = 0;
      }
    }

    migrated++;
  }

  // Commit remaining.
  if (!DRY_RUN && batchCount > 0) {
    await batch.commit();
    console.log(`  Committed final batch of ${batchCount} documents.`);
  }

  console.log("\n=== Migration Summary ===");
  console.log(`Total LLLL products:    ${productCodes.length}`);
  console.log(`Migrated (with ISBN):   ${migrated}`);
  console.log(`Skipped (no ISBN):      ${skippedNoIsbn}`);
  console.log(`Skipped (duplicate):    ${skippedDuplicate}`);
  if (DRY_RUN) {
    console.log("\n[DRY RUN] No documents were written.");
  } else {
    console.log("\nMigration complete.");
  }

  process.exit(0);
}

main().catch((err) => {
  console.error("Migration failed:", err);
  process.exit(1);
});
