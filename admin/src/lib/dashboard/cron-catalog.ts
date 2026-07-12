// Catalogue of every scheduled Cloud Function, joined against
// opsMetrics/cronHeartbeats (written by recordCronRun in
// functions/src/ops_heartbeat.ts) to compute freshness for the
// dashboard health panel. staleAfterMs is roughly 2-3x the schedule
// interval so a single slow run never flaps the indicator;
// null = never mark stale (annual jobs).

export interface CronCatalogEntry {
  name: string;
  label: string;
  scheduleLabel: string;
  staleAfterMs: number | null;
}

const MIN = 60_000;
const HOUR = 3_600_000;
const DAY = 86_400_000;

export const CRON_CATALOG: CronCatalogEntry[] = [
  {
    name: "dispatchScheduledNotificationCampaigns",
    label: "Scheduled campaigns",
    scheduleLabel: "every 5 min",
    staleAfterMs: 15 * MIN,
  },
  {
    name: "expireImpersonationSessions",
    label: "Impersonation expiry",
    scheduleLabel: "every 5 min",
    staleAfterMs: 15 * MIN,
  },
  {
    name: "sendReadingReminders",
    label: "Reading reminders",
    scheduleLabel: "hourly",
    staleAfterMs: 2.5 * HOUR,
  },
  {
    name: "processPendingUserDeletions",
    label: "Pending user deletions",
    scheduleLabel: "hourly",
    staleAfterMs: 2.5 * HOUR,
  },
  {
    name: "monitorImpersonationAnomalies",
    label: "Impersonation anomaly sweep",
    scheduleLabel: "hourly",
    staleAfterMs: 2.5 * HOUR,
  },
  {
    name: "cleanupComprehensionAudio",
    label: "Audio retention cleanup",
    scheduleLabel: "daily",
    staleAfterMs: 26 * HOUR,
  },
  {
    name: "cleanupExpiredLinkCodes",
    label: "Link-code expiry",
    scheduleLabel: "daily 02:00 LA",
    staleAfterMs: 26 * HOUR,
  },
  {
    name: "reconcileStorageUsage",
    label: "Storage usage reconcile",
    scheduleLabel: "daily 02:30 Syd",
    staleAfterMs: 26 * HOUR,
  },
  {
    name: "scrambleDemoPasswords",
    label: "Demo password scramble",
    scheduleLabel: "daily 00:05 Syd",
    staleAfterMs: 26 * HOUR,
  },
  {
    name: "pruneStaleFcmTokens",
    label: "Stale FCM token GC",
    scheduleLabel: "Mon 04:00 UTC",
    staleAfterMs: 8 * DAY,
  },
  {
    name: "reconcileStatsScheduled",
    label: "Stats reconcile",
    scheduleLabel: "Sun 03:00 UTC",
    staleAfterMs: 8 * DAY,
  },
  {
    name: "topReaderAward",
    label: "Top Reader award",
    scheduleLabel: "Mon 05:00 Syd",
    staleAfterMs: 8 * DAY,
  },
  {
    name: "annualRollover",
    label: "Annual rollover",
    scheduleLabel: "25 Jan yearly",
    staleAfterMs: null,
  },
];
