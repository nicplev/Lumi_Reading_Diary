"use client";

import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useMemo, useState } from "react";
import { toast } from "sonner";
import type { ColumnDef } from "@tanstack/react-table";
import { DataTable } from "@/components/data-table/data-table";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import { StatusBadge } from "@/components/shared/status-badge";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { formatDateTime } from "@/lib/utils";
import type {
  DeliveryIncident,
  DeliveryIncidentKind,
} from "@/lib/firestore/delivery-incidents";

type KindFilter = DeliveryIncidentKind | "all";
type StatusFilter = "open" | "all";
type PendingAction = { incident: DeliveryIncident; action: "retry" | "acknowledge" };

const SOURCE_LABELS = {
  parentOnboarding: "Parent onboarding",
  staffOnboarding: "Staff onboarding",
  notification: "Notification campaign",
} as const;

export function DeliveryIncidentsTable({
  incidents,
  initialKind,
  initialStatus,
}: {
  incidents: DeliveryIncident[];
  initialKind: KindFilter;
  initialStatus: StatusFilter;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [kind, setKind] = useState<KindFilter>(initialKind);
  const [status, setStatus] = useState<StatusFilter>(initialStatus);
  const [pending, setPending] = useState<PendingAction | null>(null);
  const [loading, setLoading] = useState(false);

  const filtered = useMemo(
    () =>
      incidents.filter(
        (item) =>
          (kind === "all" || item.kind === kind) &&
          (status === "all" || item.attentionStatus === "open")
      ),
    [incidents, kind, status]
  );

  const updateQuery = (nextKind: KindFilter, nextStatus: StatusFilter) => {
    const params = new URLSearchParams(searchParams.toString());
    if (nextKind === "all") params.delete("kind");
    else params.set("kind", nextKind);
    params.set("status", nextStatus);
    router.replace(`${pathname}?${params.toString()}`, { scroll: false });
  };

  const runAction = async () => {
    if (!pending) return;
    setLoading(true);
    try {
      const response = await fetch("/api/delivery-incidents/action", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          schoolId: pending.incident.schoolId,
          recordId: pending.incident.id,
          source: pending.incident.source,
          action: pending.action,
        }),
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? "Action failed");
      toast.success(
        pending.action === "retry"
          ? "Retry queued for failed recipients"
          : "Incident acknowledged"
      );
      setPending(null);
      router.refresh();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Action failed");
    } finally {
      setLoading(false);
    }
  };

  const columns: ColumnDef<DeliveryIncident>[] = [
    {
      accessorKey: "schoolName",
      header: "School",
      cell: ({ row }) => (
        <Link
          href={`/schools/${encodeURIComponent(row.original.schoolId)}`}
          className="font-medium text-primary hover:underline"
          onClick={(event) => event.stopPropagation()}
        >
          {row.original.schoolName}
        </Link>
      ),
    },
    {
      accessorKey: "source",
      header: "Delivery",
      cell: ({ row }) => SOURCE_LABELS[row.original.source],
    },
    {
      accessorKey: "status",
      header: "Status",
      cell: ({ row }) => <StatusBadge status={row.original.status} />,
    },
    {
      id: "counts",
      header: "Results",
      cell: ({ row }) => (
        <span className="text-sm text-muted-foreground">
          {row.original.sentCount} sent · {row.original.failedCount} failed
          {row.original.skippedCount > 0
            ? ` · ${row.original.skippedCount} skipped`
            : ""}
        </span>
      ),
    },
    {
      accessorKey: "errorSummary",
      header: "What happened",
      cell: ({ row }) => (
        <span className="block max-w-[360px] text-sm" title={row.original.errorSummary}>
          {row.original.errorSummary}
        </span>
      ),
    },
    {
      accessorKey: "createdAt",
      header: "Created",
      cell: ({ row }) =>
        row.original.createdAt ? formatDateTime(row.original.createdAt) : "—",
    },
    {
      id: "actions",
      header: "",
      cell: ({ row }) =>
        row.original.attentionStatus === "open" ? (
          <div className="flex justify-end gap-1" onClick={(event) => event.stopPropagation()}>
            {row.original.canRetry && (
              <Button
                variant="outline"
                size="sm"
                onClick={() => setPending({ incident: row.original, action: "retry" })}
              >
                Retry failed
              </Button>
            )}
            <Button
              variant="ghost"
              size="sm"
              onClick={() =>
                setPending({ incident: row.original, action: "acknowledge" })
              }
            >
              Acknowledge
            </Button>
          </div>
        ) : (
          <StatusBadge status={row.original.attentionStatus} />
        ),
    },
  ];

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-3">
        <Select
          value={kind}
          onValueChange={(value) => {
            if (!value) return;
            const next = value as KindFilter;
            setKind(next);
            updateQuery(next, status);
          }}
        >
          <SelectTrigger className="w-[220px]">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All delivery types</SelectItem>
            <SelectItem value="onboarding">Onboarding emails</SelectItem>
            <SelectItem value="notification">Notification campaigns</SelectItem>
          </SelectContent>
        </Select>
        <Select
          value={status}
          onValueChange={(value) => {
            if (!value) return;
            const next = value as StatusFilter;
            setStatus(next);
            updateQuery(kind, next);
          }}
        >
          <SelectTrigger className="w-[180px]">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="open">Open incidents</SelectItem>
            <SelectItem value="all">All incidents</SelectItem>
          </SelectContent>
        </Select>
        <span className="text-sm text-muted-foreground">
          {filtered.length} incident{filtered.length === 1 ? "" : "s"}
        </span>
      </div>

      <DataTable
        columns={columns}
        data={filtered}
        searchKey="schoolName"
        searchPlaceholder="Search by school..."
      />

      <ConfirmDialog
        open={pending !== null}
        onOpenChange={(open) => {
          if (!open && !loading) setPending(null);
        }}
        title={pending?.action === "retry" ? "Retry failed recipients?" : "Acknowledge incident?"}
        description={
          pending?.action === "retry"
            ? "A new delivery job will be created from the server-owned failed-recipient list. Successfully delivered recipients will not be selected again."
            : "This removes the incident from Needs Attention without changing its delivery history."
        }
        confirmLabel={pending?.action === "retry" ? "Queue retry" : "Acknowledge"}
        onConfirm={runAction}
        loading={loading}
      />
    </div>
  );
}
