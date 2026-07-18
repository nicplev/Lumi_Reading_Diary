import "server-only";
import { getAdminAuth, getAdminDb } from "@/lib/firebase-admin";
import {
  runDemoPreflight,
  type DemoPreflightResult,
} from "@/lib/demo/preflight-core";
import { DEMO_SCHOOL_ID_DEFAULT } from "@/lib/firestore/demo-access";

const PROJECT_ID = "lumi-ninc-au";
const SCHOOL_PORTAL_ORIGIN = "https://lumi-school-admin-au.web.app";
const SUPER_ADMIN_ORIGIN = "https://lumi-dev-admin-au.web.app";

// Kept beside the server preflight intentionally. The demo regression gate
// checks this against TermsAcceptanceService.currentTermsVersion so a mobile
// Terms version change cannot silently leave the live canary stale.
export const CURRENT_MOBILE_TERMS_VERSION = "2026-07-10";

/** Runs only inside the privileged super-admin runtime. */
export async function runLiveDemoPreflight(): Promise<DemoPreflightResult> {
  const configuredProject =
    process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID ?? PROJECT_ID;
  if (configuredProject !== PROJECT_ID) {
    throw new Error("Safety stop: the super-admin runtime targets the wrong Firebase project.");
  }

  const apiKey = process.env.NEXT_PUBLIC_FIREBASE_API_KEY?.trim() ?? "";
  if (!apiKey || apiKey === "ci") {
    throw new Error("The Firebase client configuration is unavailable.");
  }

  return runDemoPreflight({
    auth: getAdminAuth(),
    db: getAdminDb(),
    projectId: PROJECT_ID,
    demoSchoolId: DEMO_SCHOOL_ID_DEFAULT,
    portalOrigin: SCHOOL_PORTAL_ORIGIN,
    apiKey,
    // The production web key is browser-referrer restricted. These headers
    // identify the known super-admin web app without exposing a new secret.
    clientAppHeaders: { referer: `${SUPER_ADMIN_ORIGIN}/` },
    termsVersion: CURRENT_MOBILE_TERMS_VERSION,
    canary: true,
  });
}
