import { PageHeader } from "@/components/layout/page-header";
import { getAdminDb } from "@/lib/firebase-admin";
import {
  getComprehensionRecordingFlag,
  getComprehensionRetentionConfig,
} from "@lumi/server-ops";
import { FeatureControlsPanel } from "./feature-controls-panel";
import { RetentionControlsCard } from "./retention-controls-card";

export const dynamic = "force-dynamic";

export default async function FeatureControlsPage() {
  const db = getAdminDb();
  const [comprehensionRecording, comprehensionRetention] = await Promise.all([
    getComprehensionRecordingFlag(db),
    getComprehensionRetentionConfig(db),
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
      </div>
    </>
  );
}
