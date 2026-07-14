#!/usr/bin/env node
/**
 * Remove duplicate parent FCM tokens, retaining the most recently refreshed
 * owner. An FCM token identifies a physical app installation, so it must not
 * remain on multiple parent records after an account switch.
 *
 * Dry-run by default. Review its counts first, then run deliberately with
 * --apply after the enforceUniqueParentFcmToken function is deployed.
 *
 * Usage (production):
 *   GOOGLE_CLOUD_PROJECT=lumi-ninc-au node scripts/deduplicate_parent_fcm_tokens.js
 *   GOOGLE_CLOUD_PROJECT=lumi-ninc-au node scripts/deduplicate_parent_fcm_tokens.js --apply
 */

const path = require('path');

function loadAdmin() {
  try {
    return require('firebase-admin');
  } catch (_) {
    return require(require.resolve('firebase-admin', {
      paths: [path.join(__dirname, '..', 'functions', 'node_modules')],
    }));
  }
}

const admin = loadAdmin();
admin.initializeApp();
const db = admin.firestore();

const APPLY = process.argv.includes('--apply');
const PAGE_SIZE = 500;
const BATCH_SIZE = 400;

function timestampMillis(value) {
  return value && typeof value.toMillis === 'function' ? value.toMillis() : 0;
}

async function loadTokenOwners() {
  const ownersByToken = new Map();
  let last = null;

  for (;;) {
    let query = db.collectionGroup('parents')
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(PAGE_SIZE);
    if (last) query = query.startAfter(last);
    const page = await query.get();
    if (page.empty) break;

    for (const doc of page.docs) {
      const data = doc.data();
      const token = typeof data.fcmToken === 'string' ? data.fcmToken.trim() : '';
      if (!token) continue;

      const owner = {
        ref: doc.ref,
        updatedAt: timestampMillis(data.fcmTokenUpdatedAt),
        updateTime: doc.updateTime,
      };
      const owners = ownersByToken.get(token) || [];
      owners.push(owner);
      ownersByToken.set(token, owners);
    }

    last = page.docs[page.docs.length - 1];
    if (page.size < PAGE_SIZE) break;
  }

  return ownersByToken;
}

async function main() {
  console.log(`Deduplicate parent FCM tokens ${APPLY ? '(APPLY)' : '(dry-run — pass --apply to write)'}`);
  let duplicateTokens = 0;
  let staleOwners = 0;
  const ownersByToken = await loadTokenOwners();
  const staleOwnersToRemove = [];

  for (const owners of ownersByToken.values()) {
    if (owners.length < 2) continue;
    duplicateTokens++;
    // Latest successful registration is the current owner. The document ID
    // tie-breaker keeps the dry-run/apply outcome deterministic.
    owners.sort((a, b) =>
      (b.updatedAt - a.updatedAt) || a.ref.path.localeCompare(b.ref.path));
    staleOwnersToRemove.push(...owners.slice(1));
  }

  staleOwners = staleOwnersToRemove.length;
  if (APPLY) {
    for (let i = 0; i < staleOwnersToRemove.length; i += BATCH_SIZE) {
      const batch = db.batch();
      for (const owner of staleOwnersToRemove.slice(i, i + BATCH_SIZE)) {
        // Do not delete a token that was refreshed after this dry-run page
        // was read. A failed precondition aborts the batch safely for review.
        batch.update(owner.ref, {
          fcmToken: admin.firestore.FieldValue.delete(),
          fcmTokenUpdatedAt: admin.firestore.FieldValue.delete(),
        }, {lastUpdateTime: owner.updateTime});
      }
      await batch.commit();
    }
  }

  console.log(`Found ${duplicateTokens} duplicate token(s).`);
  console.log(`${APPLY ? 'Removed' : 'Would remove'} ${staleOwners} stale owner record(s).`);
}

main().then(() => process.exit(0)).catch((error) => {
  console.error(error);
  process.exit(1);
});
