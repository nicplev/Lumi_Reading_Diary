import { PageHeader } from "@/components/layout/page-header";
import { listDeletionOperations } from "@/lib/firestore/deletion-operations";
import { DeletionOperationsTable } from "./deletion-operations-table";

const allowedStatuses = [
  "all",
  "cooling-off",
  "pending",
  "processing",
  "retrying",
  "manual-review",
] as const;

export default async function DeletionOperationsPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string }>;
}) {
  const params = await searchParams;
  const status = allowedStatuses.includes(
    params.status as (typeof allowedStatuses)[number]
  )
    ? (params.status as (typeof allowedStatuses)[number])
    : "all";
  const operations = await listDeletionOperations();

  return (
    <>
      <PageHeader
        title="Deletion operations"
        description="Monitor deletion jobs and cancel staff-account deletion during its cooling-off period."
      />
      <DeletionOperationsTable operations={operations} initialStatus={status} />
    </>
  );
}
