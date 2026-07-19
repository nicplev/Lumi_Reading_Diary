import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";
import type {
  PlatformDemoAccessConfig,
  DemoAccessEmailStatus,
} from "@lumi/types";
import {
  readDemoControlValues,
  type DemoControlValues,
} from "@/lib/demo/control-model";

// The permanent demo tenant. Config is the source of truth; this is the
// fail-safe default the seed script also writes.
export const DEMO_SCHOOL_ID_DEFAULT = "lumi_demo_primary_school";
export const DEMO_ACCESS_TIMEZONE = "Australia/Sydney";

const DEFAULT_CONFIG: PlatformDemoAccessConfig = {
  schoolId: DEMO_SCHOOL_ID_DEFAULT,
  adminEmail: "support+demo@lumi-reading.com",
  teacherEmail: "support+demo.teacher@lumi-reading.com",
  parentEmail: "support+demo.parent@lumi-reading.com",
  scrambleOnlyEmails: [],
  portalLoginUrl: "https://lumi-school-admin-au.web.app/login",
  marketingUrl: "https://lumi-reading.com",
  appStoreUrl: null,
  playStoreUrl: null,
};

function toISO(ts: unknown): string {
  if (!ts || typeof ts !== "object") return "";
  if ("toDate" in ts && typeof (ts as { toDate: unknown }).toDate === "function") {
    return (ts as { toDate: () => Date }).toDate().toISOString();
  }
  return "";
}

/** The Sydney calendar day as "YYYY-MM-DD" — the demo-access dayKey. */
export function sydneyDayKey(d: Date = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: DEMO_ACCESS_TIMEZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(d);
}

export async function readDemoAccessConfig(): Promise<PlatformDemoAccessConfig> {
  const snap = await getAdminDb().doc("platformConfig/demoAccess").get();
  if (!snap.exists) return DEFAULT_CONFIG;
  const d = snap.data() ?? {};
  const str = (v: unknown, fb: string) =>
    typeof v === "string" && v.trim().length > 0 ? v.trim() : fb;
  return {
    schoolId: str(d.schoolId, DEFAULT_CONFIG.schoolId),
    adminEmail: str(d.adminEmail, DEFAULT_CONFIG.adminEmail),
    teacherEmail: str(d.teacherEmail, DEFAULT_CONFIG.teacherEmail),
    parentEmail: str(d.parentEmail, DEFAULT_CONFIG.parentEmail),
    scrambleOnlyEmails: Array.isArray(d.scrambleOnlyEmails)
      ? (d.scrambleOnlyEmails as unknown[]).filter(
          (e): e is string => typeof e === "string"
        )
      : DEFAULT_CONFIG.scrambleOnlyEmails,
    portalLoginUrl: str(d.portalLoginUrl, DEFAULT_CONFIG.portalLoginUrl),
    marketingUrl: str(d.marketingUrl, DEFAULT_CONFIG.marketingUrl),
    appStoreUrl:
      typeof d.appStoreUrl === "string" && d.appStoreUrl.length > 0
        ? d.appStoreUrl
        : null,
    playStoreUrl:
      typeof d.playStoreUrl === "string" && d.playStoreUrl.length > 0
        ? d.playStoreUrl
        : null,
  };
}

/** Whether a school is the configured demo school (gates the demo-emails tab). */
export async function isDemoSchool(schoolId: string): Promise<boolean> {
  const config = await readDemoAccessConfig();
  return schoolId === config.schoolId;
}

export interface DemoEmailHistoryItem {
  id: string;
  to: string;
  contactPerson: string;
  schoolName: string;
  status: DemoAccessEmailStatus;
  subject?: string;
  error?: string;
  createdAtISO: string;
  sentAtISO: string | null;
  onboardingId: string;
  dayKey: string;
  requestedByEmail?: string;
}

function mapEmailDoc(
  doc: FirebaseFirestore.QueryDocumentSnapshot
): DemoEmailHistoryItem {
  const data = doc.data();
  const requestedBy = data.requestedBy as { email?: string } | undefined;
  return {
    id: doc.id,
    to: data.to ?? "",
    contactPerson: data.contactPerson ?? "",
    schoolName: data.schoolName ?? "",
    status: (data.status ?? "queued") as DemoAccessEmailStatus,
    subject: data.subject,
    error: data.error,
    createdAtISO: toISO(data.createdAt),
    sentAtISO: toISO(data.sentAt) || null,
    onboardingId: data.onboardingId ?? "",
    dayKey: data.dayKey ?? "",
    requestedByEmail: requestedBy?.email,
  };
}

export interface DemoAccessView {
  today: string;
  active: boolean;
  scrambled: boolean;
  password: string | null;
  issuedAtISO: string | null;
  issuedByEmail: string | null;
  adminEmail: string;
  teacherEmail: string;
  parentEmail: string;
  portalLoginUrl: string;
  marketingUrl: string;
  readiness: DemoReadinessView | null;
  controls: DemoControlsView;
  /** Send history for THIS onboarding request, newest first. */
  history: DemoEmailHistoryItem[];
}

export interface DemoControlsView extends DemoControlValues {
  updatedAtISO: string | null;
  updatedByEmail: string | null;
}

export interface DemoReadinessView {
  ready: boolean;
  state: "ready" | "not_ready" | "stale";
  dayKey: string | null;
  checkedAtISO: string | null;
  checkedByEmail: string | null;
  checks: Array<{
    key: string;
    label: string;
    status: "pass" | "fail" | "skipped";
    detail: string;
  }>;
}

function mapReadiness(data: FirebaseFirestore.DocumentData | undefined): DemoReadinessView | null {
  if (!data) return null;
  const state = ["ready", "not_ready", "stale"].includes(data.state)
    ? (data.state as DemoReadinessView["state"])
    : "stale";
  const checks = Array.isArray(data.checks)
    ? data.checks
        .filter(
          (check: unknown): check is Record<string, unknown> =>
            !!check && typeof check === "object",
        )
        .map((check: Record<string, unknown>) => ({
          key: typeof check.key === "string" ? check.key : "unknown",
          label: typeof check.label === "string" ? check.label : "Readiness check",
          status: ["pass", "fail", "skipped"].includes(String(check.status))
            ? (check.status as "pass" | "fail" | "skipped")
            : "fail",
          detail:
            typeof check.detail === "string"
              ? check.detail
              : "No readiness detail is available.",
        }))
    : [];
  const checkedBy =
    data.checkedBy && typeof data.checkedBy === "object"
      ? (data.checkedBy as Record<string, unknown>)
      : {};
  return {
    ready: data.ready === true && state === "ready",
    state,
    dayKey: typeof data.dayKey === "string" ? data.dayKey : null,
    checkedAtISO: toISO(data.checkedAt) || null,
    checkedByEmail:
      typeof checkedBy.email === "string" ? checkedBy.email : null,
    checks,
  };
}

// State + this-request history for the onboarding detail panel. The password is
// returned ONLY while the state is live (today, unscrambled) — a super-admin who
// just provisioned needs to read it out; an expired one is never re-surfaced.
export async function getDemoAccessView(
  onboardingId: string
): Promise<DemoAccessView> {
  const db = getAdminDb();
  const [
    config,
    stateSnap,
    readinessSnap,
    emailsSnap,
    schoolSnap,
    platformAudioSnap,
    controlStatusSnap,
  ] = await Promise.all([
    readDemoAccessConfig(),
    db.doc("demoAccess/state").get(),
    db.doc("demoAccess/readinessStatus").get(),
    db
      .collection("demoAccessEmails")
      .where("onboardingId", "==", onboardingId)
      .get(),
    db.doc(`schools/${DEMO_SCHOOL_ID_DEFAULT}`).get(),
    db.doc("platformConfig/comprehensionRecording").get(),
    db.doc("demoAccess/controlStatus").get(),
  ]);

  const today = sydneyDayKey();
  const state = stateSnap.data();
  const scrambled = !!state && state.scrambledAt != null;
  const active =
    !!state &&
    state.dayKey === today &&
    !scrambled &&
    typeof state.password === "string" &&
    state.password.length > 0;

  const history = emailsSnap.docs
    .map(mapEmailDoc)
    .sort((a, b) => b.createdAtISO.localeCompare(a.createdAtISO));
  const controlValues = readDemoControlValues(
    schoolSnap.data(),
    platformAudioSnap.data(),
  );
  const controlStatus = controlStatusSnap.data();
  const controlUpdatedBy =
    controlStatus?.updatedBy && typeof controlStatus.updatedBy === "object"
      ? (controlStatus.updatedBy as Record<string, unknown>)
      : {};

  return {
    today,
    active,
    scrambled,
    password: active && typeof state?.password === "string" ? state.password : null,
    issuedAtISO: active ? toISO(state?.issuedAt) || null : null,
    issuedByEmail: active ? state?.issuedBy?.email ?? null : null,
    adminEmail: config.adminEmail,
    teacherEmail: config.teacherEmail,
    parentEmail: config.parentEmail,
    portalLoginUrl: config.portalLoginUrl,
    marketingUrl: config.marketingUrl,
    readiness: mapReadiness(readinessSnap.data()),
    controls: {
      ...controlValues,
      updatedAtISO: toISO(controlStatus?.updatedAt) || null,
      updatedByEmail:
        typeof controlUpdatedBy.email === "string"
          ? controlUpdatedBy.email
          : null,
    },
    history,
  };
}

// ALL demo-access emails, newest first — the canonical "who was given demo
// access" view on the demo school's detail page. Single-field orderBy → no
// composite index needed.
export async function listAllDemoAccessEmails(
  limit = 200
): Promise<DemoEmailHistoryItem[]> {
  const snap = await getAdminDb()
    .collection("demoAccessEmails")
    .orderBy("createdAt", "desc")
    .limit(limit)
    .get();
  return snap.docs.map(mapEmailDoc);
}
