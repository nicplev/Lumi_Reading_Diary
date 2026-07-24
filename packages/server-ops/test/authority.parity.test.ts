import test from "node:test";
import assert from "node:assert/strict";

import { assertSuperAdmin, ServerOpsAuthorizationError } from "../src/authority";

// Minimal Firestore stub: superAdmins/{uid}.get() reports existence based on the
// provided allow-list. No emulator needed — the guard only reads one doc.
function fakeDb(superAdminUids: string[]) {
  return {
    collection() {
      return {
        doc(uid: string) {
          return {
            async get() {
              return { exists: superAdminUids.includes(uid) };
            },
          };
        },
      };
    },
  } as unknown as import("firebase-admin/firestore").Firestore;
}

test("assertSuperAdmin resolves for a uid with a /superAdmins doc", async () => {
  await assertSuperAdmin(fakeDb(["super_1"]), "super_1");
});

test("assertSuperAdmin throws for a uid with no doc and no env fallback", async () => {
  const prev = process.env.SUPER_ADMIN_UIDS;
  delete process.env.SUPER_ADMIN_UIDS;
  try {
    await assert.rejects(
      () => assertSuperAdmin(fakeDb([]), "not_super"),
      ServerOpsAuthorizationError,
    );
  } finally {
    if (prev !== undefined) process.env.SUPER_ADMIN_UIDS = prev;
  }
});

test("assertSuperAdmin throws for a missing/empty uid", async () => {
  await assert.rejects(
    () => assertSuperAdmin(fakeDb([]), undefined),
    ServerOpsAuthorizationError,
  );
});

test("assertSuperAdmin honours the SUPER_ADMIN_UIDS bootstrap env", async () => {
  const prev = process.env.SUPER_ADMIN_UIDS;
  process.env.SUPER_ADMIN_UIDS = "boot_1, boot_2";
  try {
    await assertSuperAdmin(fakeDb([]), "boot_2");
  } finally {
    if (prev === undefined) delete process.env.SUPER_ADMIN_UIDS;
    else process.env.SUPER_ADMIN_UIDS = prev;
  }
});
