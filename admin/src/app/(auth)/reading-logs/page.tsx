import { PageHeader } from "@/components/layout/page-header";
import { listAllReadingLogs } from "@/lib/firestore/reading-logs";
import { GlobalReadingLogsTable } from "./global-reading-logs-table";

export default async function GlobalReadingLogsPage({
  searchParams,
}: {
  searchParams: Promise<{ validation?: string; review?: string; period?: string }>;
}) {
  const params = await searchParams;
  const validation = params.validation === "invalid" ? "invalid" : undefined;
  const review = params.review === "all" ? "all" : "open";
  const period = params.period === "today" ? "today" : "7d";
  const logs = await listAllReadingLogs({
    limit: 500,
    validation,
    review,
    period,
  });

  return (
    <>
      <PageHeader
        title="Reading Logs"
        description={
          validation === "invalid"
            ? "Reading logs excluded from statistics by server-side validation"
            : period === "today"
              ? "Reading logs created today (Sydney time)"
              : "Reading logs created in the last 7 days"
        }
      />
      <GlobalReadingLogsTable
        logs={logs}
        validationMode={validation === "invalid"}
        reviewFilter={review}
        period={period}
      />
    </>
  );
}
