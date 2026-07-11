import type { FirestoreTimestamp } from "./common";

// Demo-day rolling-access shapes. See docs/DEMO_DAY_ACCESS_PLAN.md.

// Non-secret config at platformConfig/demoAccess (client-`get`-able; nothing
// here is secret). Seeded by scripts/seed_demo_school.js.
export interface PlatformDemoAccessConfig {
  schoolId: string;
  adminEmail: string;
  teacherEmail: string;
  parentEmail: string;
  scrambleOnlyEmails: string[];
  portalLoginUrl: string;
  marketingUrl: string;
  appStoreUrl: string | null;
  playStoreUrl: string | null;
}

export type DemoAccessRole = "admin" | "teacher" | "parent";

export interface DemoAccessAccount {
  role: DemoAccessRole;
  email: string;
  uid: string;
}

export interface DemoAccessLastEmail {
  to: string | null;
  onboardingId: string | null;
  sentAt: FirestoreTimestamp | null;
  status: "sent" | "failed" | null;
}

// The single demoAccess/state doc. Contains the plaintext day password →
// Admin-SDK-only (firestore.rules deny-all).
export interface DemoAccessState {
  dayKey: string; // Sydney YYYY-MM-DD
  password: string;
  issuedAt: FirestoreTimestamp;
  issuedBy: { uid: string; email?: string };
  accounts: DemoAccessAccount[];
  scrambledAt: FirestoreTimestamp | null;
  lastEmail: DemoAccessLastEmail | null;
}

export type DemoAccessEmailStatus = "queued" | "processing" | "sent" | "failed";

// A demoAccessEmails/{id} queue doc — also the permanent paper-trail record
// (never deleted). Admin-SDK-only.
export interface DemoAccessEmailDoc {
  onboardingId: string;
  to: string;
  contactPerson: string;
  schoolName: string;
  dayKey: string;
  requestedBy: { uid: string; email?: string };
  status: DemoAccessEmailStatus;
  subject?: string;
  error?: string;
  createdAt: FirestoreTimestamp;
  sentAt?: FirestoreTimestamp | null;
}
