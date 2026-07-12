import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import { getComprehensionRetentionConfig } from "@lumi/server-ops";
import { CRON_CATALOG } from "@/lib/dashboard/cron-catalog";
import type {
  ActivityLogItem,
  AdminActionItem,
  AttentionItem,
  CategoryUsage,
  CronHealth,
  DashboardPayload,
  HealthSection,
  PipelineItem,
  StorageHistoryPoint,
  StorageSection,
  StorageStatus,
  TrendPoint,
} from "@/lib/dashboard/types";
import { getStudentCount } from "./students";
import { getRecentActivity } from "./reading-logs";
import { listAuditLogs } from "./audit-log";
import { getRecentOnboardingRequests } from "./onboarding";
import { listFeedback } from "./feedback";

const SYDNEY_TZ = "Australia/Sydney";
const DAY_MS = 86_400_000;
const TREND_DAYS = 14;

function toISO(ts: unknown): string {
  if (!ts || typeof ts !== "object") return "";
  if ("toDate" in ts && typeof (ts as { toDate: unknown }).toDate === "function") {
    return (ts as { toDate: () => Date }).toDate().toISOString();
  }
  return "";
}

// en-CA renders as YYYY-MM-DD — same keying the storage reconcile uses,
// so trend and storage history bucket identically.
const sydneyDate = new Intl.DateTimeFormat("en-CA", {
  timeZone: SYDNEY_TZ,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});

function readUsage(raw: unknown): CategoryUsage {
  const r = (raw ?? {}) as Record<string, unknown>;
  return {
    bytes: typeof r.bytes === "number" ? Math.max(0, r.bytes) : 0,
    objects: typeof r.objects === "number" ? Math.max(0, r.objects) : 0,
  };
}

interface SchoolRef {
  id: string;
  name: string;
  ref: FirebaseFirestore.DocumentReference;
}

// ── Reading activity: one 14-day fan-out read powers the KPI counts,
// the daily trend, and weekly-active-students. Fine at current scale
// (a handful of schools); when log volume grows, switch the trend to
// per-day count() queries and drop the minutes series.
async function readActivity(schools: SchoolRef[], now: Date) {
  const since = new Date(now.getTime() - TREND_DAYS * DAY_MS);
  const sevenDaysAgo = now.getTime() - 7 * DAY_MS;
  const today = sydneyDate.format(now);

  const buckets = new Map<string, { logs: number; minutes: number }>();
  for (let i = TREND_DAYS - 1; i >= 0; i--) {
    buckets.set(sydneyDate.format(new Date(now.getTime() - i * DAY_MS)), {
      logs: 0,
      minutes: 0,
    });
  }

  let logsToday = 0;
  let logsThisWeek = 0;
  let logsLastWeek = 0;
  const weeklyActive = new Set<string>();

  await Promise.all(
    schools.map(async (school) => {
      const snap = await school.ref
        .collection("readingLogs")
        .where("createdAt", ">=", Timestamp.fromDate(since))
        .select("studentId", "minutesRead", "createdAt", "validationStatus")
        .get();

      for (const doc of snap.docs) {
        const data = doc.data();
        if (String(data.validationStatus ?? "") === "invalid") continue;
        const created = data.createdAt?.toDate?.() as Date | undefined;
        if (!created) continue;
        const minutes =
          typeof data.minutesRead === "number" ? data.minutesRead : 0;

        const key = sydneyDate.format(created);
        const bucket = buckets.get(key);
        if (bucket) {
          bucket.logs += 1;
          bucket.minutes += minutes;
        }
        if (key === today) logsToday += 1;
        if (created.getTime() >= sevenDaysAgo) {
          logsThisWeek += 1;
          if (data.studentId) weeklyActive.add(String(data.studentId));
        } else {
          logsLastWeek += 1;
        }
      }
    })
  );

  const trend: TrendPoint[] = Array.from(buckets.entries()).map(
    ([date, v]) => ({ date, logs: v.logs, minutes: v.minutes })
  );

  return {
    trend,
    totalTrendMinutes: trend.reduce((sum, p) => sum + p.minutes, 0),
    logsToday,
    logsThisWeek,
    logsLastWeek,
    weeklyActiveStudents: weeklyActive.size,
  };
}

// ── Storage card: reads the counter doc maintained by the storage
// triggers + nightly reconcile (functions/src/storage_usage.ts).
// Thresholds compare against AUDIO bytes — the growth the dashboard
// exists to catch — while totals stay visible for context.
async function readStorage(
  db: FirebaseFirestore.Firestore,
  schoolNames: Map<string, string>
): Promise<StorageSection> {
  const [usageSnap, alertsSnap] = await Promise.all([
    db.doc("opsMetrics/storageUsage").get(),
    db.doc("platformConfig/storageAlerts").get(),
  ]);

  const alerts = alertsSnap.data();
  const thresholds =
    alerts &&
    typeof alerts.warnBytes === "number" &&
    typeof alerts.criticalBytes === "number"
      ? { warnBytes: alerts.warnBytes, criticalBytes: alerts.criticalBytes }
      : null;

  const usage = usageSnap.data();
  if (!usageSnap.exists || !usage) {
    return {
      available: false,
      totalBytes: 0,
      totalObjects: 0,
      audioBytes: 0,
      audioObjects: 0,
      categories: {},
      topSchools: [],
      history: [],
      lastReconcileAt: null,
      driftBytes: null,
      thresholds,
      status: "unknown",
    };
  }

  const categoriesRaw = (usage.categories ?? {}) as Record<string, unknown>;
  const categories: Record<string, CategoryUsage> = {};
  for (const [key, value] of Object.entries(categoriesRaw)) {
    categories[key] = readUsage(value);
  }
  const audio = categories.comprehensionAudio ?? { bytes: 0, objects: 0 };

  const perSchoolRaw = (usage.audioPerSchool ?? {}) as Record<string, unknown>;
  const topSchools = Object.entries(perSchoolRaw)
    .map(([schoolId, value]) => {
      const u = readUsage(value);
      return {
        schoolId,
        schoolName: schoolNames.get(schoolId) ?? schoolId,
        bytes: u.bytes,
        objects: u.objects,
      };
    })
    .sort((a, b) => b.bytes - a.bytes)
    .slice(0, 5);

  const history: StorageHistoryPoint[] = Array.isArray(usage.history)
    ? (usage.history as Array<Record<string, unknown>>)
        .filter((h) => typeof h?.date === "string")
        .map((h) => ({
          date: String(h.date),
          totalBytes: typeof h.totalBytes === "number" ? h.totalBytes : 0,
          audioBytes: typeof h.audioBytes === "number" ? h.audioBytes : 0,
        }))
    : [];

  let status: StorageStatus = "ok";
  if (thresholds) {
    if (audio.bytes >= thresholds.criticalBytes) status = "critical";
    else if (audio.bytes >= thresholds.warnBytes) status = "warn";
  }

  const lastReconcile = usage.lastReconcile as
    | Record<string, unknown>
    | undefined;

  return {
    available: true,
    totalBytes: Math.max(0, Number(usage.totalBytes) || 0),
    totalObjects: Math.max(0, Number(usage.totalObjects) || 0),
    audioBytes: audio.bytes,
    audioObjects: audio.objects,
    categories,
    topSchools,
    history,
    lastReconcileAt: lastReconcile ? toISO(lastReconcile.at) || null : null,
    driftBytes:
      lastReconcile && typeof lastReconcile.driftBytes === "number"
        ? lastReconcile.driftBytes
        : null,
    thresholds,
    status,
  };
}

async function readHealth(
  db: FirebaseFirestore.Firestore,
  now: Date
): Promise<HealthSection> {
  const [aggSnap, cursorSnap, heartbeatsSnap, retention] = await Promise.all([
    db.doc("platformConfig/incrementalAggregation").get(),
    db.doc("platformConfig/statsReconcileCursor").get(),
    db.doc("opsMetrics/cronHeartbeats").get(),
    getComprehensionRetentionConfig(db),
  ]);

  const agg = aggSnap.data() ?? {};
  const heartbeats = (heartbeatsSnap.data() ?? {}) as Record<string, unknown>;

  const crons: CronHealth[] = CRON_CATALOG.map((entry) => {
    const beat = heartbeats[entry.name] as Record<string, unknown> | undefined;
    const lastRunAt = beat ? toISO(beat.lastRunAt) || null : null;
    let freshness: CronHealth["freshness"] = "unknown";
    if (lastRunAt) {
      const age = now.getTime() - new Date(lastRunAt).getTime();
      freshness =
        entry.staleAfterMs !== null && age > entry.staleAfterMs
          ? "stale"
          : "fresh";
    }
    return {
      name: entry.name,
      label: entry.label,
      scheduleLabel: entry.scheduleLabel,
      lastRunAt,
      lastStatus: beat && typeof beat.lastStatus === "string" ? beat.lastStatus : null,
      note: beat && typeof beat.note === "string" ? beat.note : null,
      freshness,
    };
  });

  return {
    incrementalAggregation: {
      studentStats: agg.studentStats === true,
      classStats: agg.classStats === true,
    },
    retention: {
      enabled: retention.enabled,
      lastRunAt: retention.lastRunAt,
      deletedCount: retention.lastRunStats?.deletedCount ?? null,
      failedCount: retention.lastRunStats?.failedCount ?? null,
    },
    statsReconcileUpdatedAt: toISO(cursorSnap.data()?.updatedAt) || null,
    crons,
  };
}

// ── Needs attention: unions the scattered failure/queue signals into
// severity-ranked rows. Per-school fan-out with single-field filters
// only — no composite indexes needed at this scale; the collection-group
// + composite-index variant is the migration path when school count grows.
async function readAttention(
  db: FirebaseFirestore.Firestore,
  schools: SchoolRef[],
  now: Date
): Promise<AttentionItem[]> {
  const sevenDaysAgo = now.getTime() - 7 * DAY_MS;

  let failedCampaigns = 0;
  let failedEmails = 0;
  let invalidLogs = 0;

  const perSchool = Promise.all(
    schools.map(async (school) => {
      const [campaignsSnap, parentEmails, staffEmails, invalidSnap] =
        await Promise.all([
          school.ref
            .collection("notificationCampaigns")
            .where("status", "in", ["failed", "partial"])
            .select("createdAt")
            .get(),
          school.ref
            .collection("parentOnboardingEmails")
            .where("status", "==", "failed")
            .count()
            .get(),
          school.ref
            .collection("staffOnboardingEmails")
            .where("status", "==", "failed")
            .count()
            .get(),
          school.ref
            .collection("readingLogs")
            .where("validationStatus", "==", "invalid")
            .count()
            .get(),
        ]);

      failedCampaigns += campaignsSnap.docs.filter((doc) => {
        const created = doc.data().createdAt?.toDate?.() as Date | undefined;
        return created ? created.getTime() >= sevenDaysAgo : true;
      }).length;
      failedEmails +=
        parentEmails.data().count + staffEmails.data().count;
      invalidLogs += invalidSnap.data().count;
    })
  );

  const [
    ,
    deletionRequests,
    newFeedback,
    newLeads,
    pendingDeletions,
  ] = await Promise.all([
    perSchool,
    // orderBy(createdAt) routes this through the existing
    // (status, createdAt) COLLECTION_GROUP composite index — a bare
    // single-field CG equality would demand a CG index override.
    db
      .collectionGroup("deletionRequests")
      .where("status", "==", "pending")
      .orderBy("createdAt", "desc")
      .count()
      .get(),
    db.collection("feedback").where("status", "==", "new").count().get(),
    db
      .collection("schoolOnboarding")
      .where("status", "in", ["demo", "interested"])
      .count()
      .get(),
    db.collection("pendingUserDeletions").count().get(),
  ]);

  const items: AttentionItem[] = [
    {
      key: "failedCampaigns",
      severity: "error" as const,
      count: failedCampaigns,
      label: "notification campaign(s) failed or partial in the last 7 days",
      href: "/schools",
    },
    {
      key: "failedOnboardingEmails",
      severity: "error" as const,
      count: failedEmails,
      label: "onboarding email(s) failed to send",
      href: "/schools",
    },
    {
      key: "invalidReadingLogs",
      severity: "warn" as const,
      count: invalidLogs,
      label: "reading log(s) flagged invalid by validation",
      href: "/reading-logs",
    },
    {
      key: "pendingDeletionRequests",
      severity: "warn" as const,
      count: deletionRequests.data().count,
      label: "community-book deletion request(s) awaiting review",
      href: "/community-books",
    },
    {
      key: "newFeedback",
      severity: "info" as const,
      count: newFeedback.data().count,
      label: "new feedback item(s) to triage",
      href: "/feedback",
    },
    {
      key: "newLeads",
      severity: "info" as const,
      count: newLeads.data().count,
      label: "new onboarding lead(s) (demo / interested)",
      href: "/onboarding",
    },
    {
      key: "pendingUserDeletions",
      severity: "info" as const,
      count: pendingDeletions.data().count,
      label: "user deletion(s) in the 24h cool-off queue",
      href: "/operations",
    },
  ];

  return items.filter((item) => item.count > 0);
}

async function readActivityFeeds(): Promise<DashboardPayload["activity"]> {
  const [recentLogs, auditLogs, onboarding, feedback] = await Promise.all([
    getRecentActivity(20),
    listAuditLogs({ limit: 20 }),
    getRecentOnboardingRequests(5),
    listFeedback(5),
  ]);

  const readingLogs: ActivityLogItem[] = recentLogs.map((log) => ({
    id: log.id,
    schoolId: log.schoolId,
    studentId: log.studentId,
    minutesRead: log.minutesRead,
    status: log.status,
    bookTitles: log.bookTitles,
    createdAt: log.createdAt.toISOString(),
  }));

  const adminActions: AdminActionItem[] = auditLogs.map((entry) => ({
    id: entry.id,
    action: entry.action,
    performedByEmail: entry.performedByEmail ?? null,
    targetType: entry.targetType,
    targetId: entry.targetId,
    schoolId: entry.schoolId ?? null,
    createdAt: entry.createdAt,
  }));

  const pipeline: PipelineItem[] = [
    ...onboarding.map((req) => ({
      type: "onboarding" as const,
      id: req.id ?? "",
      title: req.schoolName ?? "Unknown school",
      status: String(req.status ?? ""),
      createdAt: toISO(req.createdAt),
      href: `/onboarding/${req.id}`,
    })),
    ...feedback.map((item) => ({
      type: "feedback" as const,
      id: item.id,
      title:
        item.description.length > 80
          ? `${item.description.slice(0, 80)}…`
          : item.description,
      status: item.status,
      createdAt: item.createdAt,
      href: "/feedback",
    })),
  ].sort((a, b) => b.createdAt.localeCompare(a.createdAt));

  return { readingLogs, adminActions, pipeline };
}

export async function getDashboardData(): Promise<DashboardPayload> {
  const db = getAdminDb();
  const now = new Date();

  const schoolsSnap = await db.collection("schools").get();
  const schools: SchoolRef[] = schoolsSnap.docs.map((doc) => ({
    id: doc.id,
    name: (doc.data().name as string) ?? doc.id,
    ref: doc.ref,
  }));
  const schoolNames = new Map(schools.map((s) => [s.id, s.name]));
  const activeSchools = schoolsSnap.docs.filter(
    (doc) => doc.data().isActive === true
  ).length;

  const [
    activeStudents,
    activity,
    storage,
    health,
    attention,
    feeds,
    onboardingInProgress,
  ] = await Promise.all([
    getStudentCount(),
    readActivity(schools, now),
    readStorage(db, schoolNames),
    readHealth(db, now),
    readAttention(db, schools, now),
    readActivityFeeds(),
    db
      .collection("schoolOnboarding")
      .where("status", "in", ["demo", "interested", "registered", "setupInProgress"])
      .count()
      .get()
      .then((snap) => snap.data().count),
  ]);

  return {
    generatedAt: now.toISOString(),
    kpis: {
      activeSchools,
      activeStudents,
      logsToday: activity.logsToday,
      logsThisWeek: activity.logsThisWeek,
      logsLastWeek: activity.logsLastWeek,
      weeklyActiveStudents: activity.weeklyActiveStudents,
      onboardingInProgress,
    },
    trend: activity.trend,
    totalTrendMinutes: activity.totalTrendMinutes,
    storage,
    health,
    attention,
    activity: feeds,
  };
}
