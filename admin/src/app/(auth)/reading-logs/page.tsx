import { PageHeader } from "@/components/layout/page-header";
import { listAllReadingLogs } from "@/lib/firestore/reading-logs";
import { GlobalReadingLogsTable } from "./global-reading-logs-table";

export default async function GlobalReadingLogsPage() {
  const logs = await listAllReadingLogs({ limit: 500 });

  return (
    <>
      <PageHeader
        title="Reading Logs"
        description="Recent reading logs across all schools (last 7 days)"
      />
      <GlobalReadingLogsTable logs={logs} />
    </>
  );
}
