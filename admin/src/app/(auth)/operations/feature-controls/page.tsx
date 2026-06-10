import { PageHeader } from "@/components/layout/page-header";
import { getAdminDb } from "@/lib/firebase-admin";
import { getComprehensionRecordingFlag } from "@lumi/server-ops";
import { FeatureControlsPanel } from "./feature-controls-panel";

export const dynamic = "force-dynamic";

export default async function FeatureControlsPage() {
  const comprehensionRecording = await getComprehensionRecordingFlag(
    getAdminDb()
  );

  return (
    <>
      <PageHeader
        title="Feature Controls"
        description="Platform-wide kill switches. These override every school's own settings."
      />
      <FeatureControlsPanel initialFlag={comprehensionRecording} />
    </>
  );
}
