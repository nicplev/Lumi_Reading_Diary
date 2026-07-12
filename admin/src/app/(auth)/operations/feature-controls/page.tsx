import { PageHeader } from "@/components/layout/page-header";
import { getAdminDb } from "@/lib/firebase-admin";
import {
  getComprehensionRecordingFlag,
  getComprehensionRetentionConfig,
  getStorageAlertsConfig,
} from "@lumi/server-ops";
import { FeatureControlsPanel } from "./feature-controls-panel";
import { RetentionControlsCard } from "./retention-controls-card";
import {
  StorageAlertsCard,
  type StorageUsageSummary,
} from "./storage-alerts-card";

export const dynamic = "force-dynamic";

function toISO(ts: unknown): string | null {
  if (!ts || typeof ts !== "object") return null;
  if ("toDate" in ts && typeof (ts as { toDate: unknown }).toDate === "function") {
    return (ts as { toDate: () => Date }).toDate().toISOString();
  }
  return null;
}

async function getStorageUsageSummary(
  db: FirebaseFirestore.Firestore
): Promise<StorageUsageSummary | null> {
  const snap = await db.doc("opsMetrics/storageUsage").get();
  const data = snap.data();
  if (!snap.exists || !data) return null;
  const audio = (data.categories as Record<string, { bytes?: number }>)
    ?.comprehensionAudio;
  const lastReconcile = data.lastReconcile as
    | Record<string, unknown>
    | undefined;
  return {
    audioBytes: typeof audio?.bytes === "number" ? Math.max(0, audio.bytes) : 0,
    totalBytes: Math.max(0, Number(data.totalBytes) || 0),
    lastReconcileAt: lastReconcile ? toISO(lastReconcile.at) : null,
  };
}

export default async function FeatureControlsPage() {
  const db = getAdminDb();
  const [
    comprehensionRecording,
    comprehensionRetention,
    storageAlerts,
    storageUsage,
  ] = await Promise.all([
    getComprehensionRecordingFlag(db),
    getComprehensionRetentionConfig(db),
    getStorageAlertsConfig(db),
    getStorageUsageSummary(db),
  ]);

  return (
    <>
      <PageHeader
        title="Feature Controls"
        description="Platform-wide kill switches and retention policy. These override every school's own settings."
      />
      <div className="space-y-6">
        <FeatureControlsPanel initialFlag={comprehensionRecording} />
        <RetentionControlsCard initialConfig={comprehensionRetention} />
        <StorageAlertsCard initialConfig={storageAlerts} usage={storageUsage} />
      </div>
    </>
  );
}
