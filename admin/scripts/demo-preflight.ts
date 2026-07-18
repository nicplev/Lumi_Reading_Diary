#!/usr/bin/env -S pnpm exec tsx

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  applicationDefault,
  deleteApp,
  getApps,
  initializeApp,
} from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import {
  DemoPreflightError,
  runDemoPreflight,
} from "../src/lib/demo/preflight-core";

const PROJECT_ID = "lumi-ninc-au";
const DEMO_SCHOOL_ID = "lumi_demo_primary_school";
const PORTAL_ORIGIN = "https://lumi-school-admin-au.web.app";
const REPO_ROOT = resolve(import.meta.dirname, "../..");

function fail(message: string): never {
  throw new Error(message);
}

function plistValue(key: string): string {
  return execFileSync(
    "plutil",
    ["-extract", key, "raw", resolve(REPO_ROOT, "ios/Runner/GoogleService-Info.plist")],
    { encoding: "utf8" },
  ).trim();
}

function currentTermsVersion(): string {
  const source = readFileSync(
    resolve(REPO_ROOT, "lib/services/terms_acceptance_service.dart"),
    "utf8",
  );
  return (
    source.match(/currentTermsVersion\s*=\s*'([^']+)'/)?.[1] ??
    fail("Could not resolve the current mobile Terms version.")
  );
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const projectArg = args.find((arg) => arg.startsWith("--project="));
  const projectId = projectArg?.slice("--project=".length) ?? "";
  const canary = args.includes("--canary");
  const known = args.every(
    (arg) => arg === "--" || arg === "--canary" || arg.startsWith("--project="),
  );
  if (!known || projectId !== PROJECT_ID) {
    fail(`Usage: pnpm demo:preflight -- --project=${PROJECT_ID} [--canary]`);
  }

  if (getApps().length === 0) {
    initializeApp({ credential: applicationDefault(), projectId: PROJECT_ID });
  }

  const result = await runDemoPreflight({
    auth: getAuth(),
    db: getFirestore(),
    projectId: PROJECT_ID,
    demoSchoolId: DEMO_SCHOOL_ID,
    portalOrigin: PORTAL_ORIGIN,
    apiKey: plistValue("API_KEY"),
    clientAppHeaders: {
      "x-ios-bundle-identifier": plistValue("BUNDLE_ID"),
    },
    termsVersion: currentTermsVersion(),
    canary,
  });

  console.log(`Lumi demo preflight — ${result.dayKey} Sydney`);
  console.log("No credential, token, UID, child name, or document ID is printed.\n");
  for (const check of result.checks) {
    console.log(`  ${check.status.toUpperCase().padEnd(7)} ${check.label} — ${check.detail}`);
  }
  console.log("\nREADY — the automated demo preflight passed.");
}

main()
  .catch((error) => {
    if (error instanceof DemoPreflightError) {
      console.error(`Lumi demo preflight — ${error.result.dayKey} Sydney`);
      console.error("No credential, token, UID, child name, or document ID is printed.\n");
      for (const check of error.result.checks) {
        console.error(
          `  ${check.status.toUpperCase().padEnd(7)} ${check.label} — ${check.detail}`,
        );
      }
    }
    console.error(`\nNOT READY — ${error instanceof Error ? error.message : "unknown preflight failure"}`);
    process.exitCode = 1;
  })
  .finally(async () => {
    await Promise.all(getApps().map((app) => deleteApp(app)));
  });
