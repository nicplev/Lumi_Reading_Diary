// Shared shapes for the live dashboard. Kept out of the "server-only"
// data layer so client components can import them type-safely.

export interface DashboardKpis {
  activeSchools: number;
  activeStudents: number;
  logsToday: number;
  logsThisWeek: number;
  logsLastWeek: number;
  weeklyActiveStudents: number;
  onboardingInProgress: number;
}

export interface TrendPoint {
  date: string;
  logs: number;
  minutes: number;
}

export interface CategoryUsage {
  bytes: number;
  objects: number;
}

export interface StorageHistoryPoint {
  date: string;
  totalBytes: number;
  audioBytes: number;
}

export type StorageStatus = "ok" | "warn" | "critical" | "unknown";

export interface StorageSection {
  available: boolean;
  totalBytes: number;
  totalObjects: number;
  audioBytes: number;
  audioObjects: number;
  categories: Record<string, CategoryUsage>;
  topSchools: Array<{
    schoolId: string;
    schoolName: string;
    bytes: number;
    objects: number;
  }>;
  history: StorageHistoryPoint[];
  lastReconcileAt: string | null;
  driftBytes: number | null;
  thresholds: { warnBytes: number; criticalBytes: number } | null;
  status: StorageStatus;
}

export type CronFreshness = "fresh" | "stale" | "unknown";

export interface CronHealth {
  name: string;
  label: string;
  scheduleLabel: string;
  lastRunAt: string | null;
  lastStatus: string | null;
  note: string | null;
  freshness: CronFreshness;
}

export interface HealthSection {
  incrementalAggregation: { studentStats: boolean; classStats: boolean };
  retention: {
    enabled: boolean;
    lastRunAt: string | null;
    deletedCount: number | null;
    failedCount: number | null;
  };
  statsReconcileUpdatedAt: string | null;
  crons: CronHealth[];
}

export type AttentionSeverity = "info" | "warn" | "error";

export interface AttentionItem {
  key: string;
  severity: AttentionSeverity;
  count: number;
  label: string;
  href: string;
}

export interface ActivityLogItem {
  id: string;
  schoolId: string;
  studentId: string;
  minutesRead: number;
  status: string;
  bookTitles: string[];
  createdAt: string;
}

export interface AdminActionItem {
  id: string;
  action: string;
  performedByEmail: string | null;
  targetType: string;
  targetId: string;
  schoolId: string | null;
  createdAt: string;
}

export interface PipelineItem {
  type: "onboarding" | "feedback";
  id: string;
  title: string;
  status: string;
  createdAt: string;
  href: string;
}

export interface DashboardPayload {
  generatedAt: string;
  kpis: DashboardKpis;
  trend: TrendPoint[];
  totalTrendMinutes: number;
  storage: StorageSection;
  health: HealthSection;
  attention: AttentionItem[];
  activity: {
    readingLogs: ActivityLogItem[];
    adminActions: AdminActionItem[];
    pipeline: PipelineItem[];
  };
}
