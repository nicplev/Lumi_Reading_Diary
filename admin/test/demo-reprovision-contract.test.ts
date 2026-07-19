import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import test from "node:test";
import { demoAccessActionSchema } from "../src/lib/validations/onboarding";

test("demo access actions distinguish preparation, reprovision and email", () => {
  for (const action of ["provision", "reprovision", "sendEmail"] as const) {
    assert.deepEqual(demoAccessActionSchema.parse({ action }), { action });
  }
  assert.equal(
    demoAccessActionSchema.safeParse({
      action: "reprovision",
      schoolId: "attacker-controlled",
    }).success,
    false,
  );
  assert.equal(
    demoAccessActionSchema.safeParse({ action: "rotatePassword" }).success,
    false,
  );
});

test("active UI requests explicit reprovision and the route applies tighter limits", () => {
  const panel = readFileSync(
    resolve("admin/src/app/(auth)/onboarding/[id]/demo-access-panel.tsx"),
    "utf8",
  );
  const route = readFileSync(
    resolve("admin/src/app/api/onboarding/[id]/demo-access/route.ts"),
    "utf8",
  );

  assert.equal(
    panel.includes('view.active ? "reprovision" : "provision"'),
    true,
  );
  assert.equal(
    panel.includes("body: JSON.stringify({ action: preparationAction })"),
    true,
  );
  assert.equal(route.includes('parsed.action === "reprovision"'), true);
  assert.equal(route.includes("max: reprovision ? 3 : 5"), true);
  assert.equal(route.includes("max: reprovision ? 6 : 10"), true);
});

test("reprovision always reseeds, rotates and advances reset-control status", () => {
  const orchestration = readFileSync(
    resolve("admin/src/lib/onboarding/demo-access.ts"),
    "utf8",
  );
  const passwordProvisioner = readFileSync(
    resolve("packages/server-ops/src/provisionDemoAccess.ts"),
    "utf8",
  );
  const reseed = readFileSync(
    resolve("packages/server-ops/src/demoSchool/reseed.ts"),
    "utf8",
  );

  assert.equal(orchestration.includes('mode === "reprovision"'), true);
  assert.equal(
    orchestration.includes('obSnap.data()?.status !== "demo"'),
    true,
  );
  assert.equal(orchestration.includes("forceRotate: forceRefresh"), true);
  assert.equal(
    passwordProvisioner.includes("params.forceRotate !== true"),
    true,
  );
  assert.equal(
    reseed.includes('db.doc("demoAccess/controlStatus")'),
    true,
  );
  assert.equal(reseed.includes("resetByReseed: { trigger, leaseId }"), true);
});
