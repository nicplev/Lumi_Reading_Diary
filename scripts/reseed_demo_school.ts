#!/usr/bin/env -S pnpm exec tsx

import { userInfo } from "node:os";
import { applicationDefault, getApps, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import {
  buildDemoSchoolPlan,
  demoSchoolConstants,
  reseedDemoSchool,
} from "../packages/server-ops/src/index";

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const dryRun = args.includes("--dry-run");
  const confirmed = args.includes("--yes");
  const projectArg = args.find((arg) => arg.startsWith("--project="));
  const projectId = projectArg?.slice("--project=".length) || "";
  const known = args.every(
    (arg) =>
      arg === "--dry-run" || arg === "--yes" || arg.startsWith("--project=")
  );

  if (!known) {
    throw new Error(
      "Unknown argument. Usage: pnpm exec tsx scripts/reseed_demo_school.ts --dry-run | --project=lumi-ninc-au --yes"
    );
  }

  const plan = buildDemoSchoolPlan();
  const summary = {
  school: `${plan.school.id} (${plan.school.data.name})`,
  authUsers: plan.authUsers.length,
  staff: plan.users.length,
  parents: plan.parents.length,
  classes: plan.classes.length,
  students: plan.students.length,
  books: plan.books.length,
  readingLogs: plan.logs.length,
  comments: plan.comments.length,
  allocations: plan.allocations.map((item) => item.id),
  linkCodes: plan.linkCodes.length,
  };

  if (dryRun) {
    console.log(JSON.stringify(summary, null, 2));
    return;
  }

// Destructive use is deliberately non-interactive and exact-target only. This
// prevents a mistyped environment variable or an unattended shell prompt from
// resetting the wrong Firebase project.
  if (!confirmed || projectId !== "lumi-ninc-au") {
    throw new Error(
      "Safety stop: destructive reseed requires both --project=lumi-ninc-au and --yes. Run --dry-run first."
    );
  }

  if (getApps().length === 0) {
    initializeApp({
      credential: applicationDefault(),
      projectId,
      storageBucket:
        process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET ??
        "lumi-ninc-au.firebasestorage.app",
    });
  }

  console.log(
    `Reseeding ${demoSchoolConstants.schoolId} in Firebase project ${projectId}...`
  );
  const result = await reseedDemoSchool(
    getAuth(),
    getFirestore(),
    getStorage(),
    { uid: `cli:${userInfo().username}` },
    { trigger: "cli" }
  );
  console.log(JSON.stringify(result, null, 2));
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
