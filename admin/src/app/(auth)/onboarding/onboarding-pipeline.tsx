"use client";

import { useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { toast } from "sonner";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { StatusBadge } from "@/components/shared/status-badge";
import { DataTable } from "@/components/data-table/data-table";
import type { OnboardingListItem } from "@/lib/firestore/onboarding";
import { onboardingColumns } from "./onboarding-columns";
import { NewRequestDialog } from "./new-request-dialog";
import { Button } from "@/components/ui/button";

const STAGES = [
  { value: "demo", label: "Demo", color: "bg-cyan-100 dark:bg-cyan-900" },
  { value: "interested", label: "Interested", color: "bg-indigo-100 dark:bg-indigo-900" },
  { value: "registered", label: "Registered", color: "bg-teal-100 dark:bg-teal-900" },
  { value: "setupInProgress", label: "Setup", color: "bg-amber-100 dark:bg-amber-900" },
  { value: "active", label: "Active", color: "bg-green-100 dark:bg-green-900" },
  { value: "suspended", label: "Suspended", color: "bg-red-100 dark:bg-red-900" },
] as const;

interface OnboardingPipelineProps {
  requests: OnboardingListItem[];
  initialView?: "leads";
}

export function OnboardingPipeline({
  requests,
  initialView,
}: OnboardingPipelineProps) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [selectedView, setSelectedView] = useState<string | null>(
    initialView ?? null
  );
  const [dragItem, setDragItem] = useState<string | null>(null);

  const getStageItems = (stage: string) =>
    requests.filter((r) => r.status === stage);

  const filteredRequests =
    selectedView === "leads"
      ? requests.filter((r) => r.status === "demo" || r.status === "interested")
      : selectedView
        ? requests.filter((r) => r.status === selectedView)
        : requests;

  const changeView = (view: string | null) => {
    setSelectedView(view);
    const params = new URLSearchParams(searchParams.toString());
    if (view === "leads") params.set("view", "leads");
    else params.delete("view");
    const query = params.toString();
    router.replace(query ? `${pathname}?${query}` : pathname, { scroll: false });
  };

  const handleDrop = async (targetStage: string) => {
    if (!dragItem || !targetStage) return;

    const item = requests.find((r) => r.id === dragItem);
    if (!item || item.status === targetStage) {
      setDragItem(null);
      return;
    }

    try {
      const res = await fetch(`/api/onboarding/${dragItem}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "updateStatus", status: targetStage }),
      });
      if (!res.ok) throw new Error("Failed to update status");
      toast.success(
        `Moved "${item.schoolName}" to ${STAGES.find((s) => s.value === targetStage)?.label}`
      );
      router.refresh();
    } catch {
      toast.error("Failed to update status");
    } finally {
      setDragItem(null);
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <Button
            variant={selectedView === "leads" ? "default" : "outline"}
            size="sm"
            onClick={() => changeView(selectedView === "leads" ? null : "leads")}
          >
            Open leads ({requests.filter((r) => r.status === "demo" || r.status === "interested").length})
          </Button>
          {selectedView && selectedView !== "leads" && (
            <Button variant="ghost" size="sm" onClick={() => changeView(null)}>
              Show all
            </Button>
          )}
        </div>
        <NewRequestDialog />
      </div>

      {/* Kanban Board */}
      <div className="grid gap-3 md:grid-cols-3 lg:grid-cols-6">
        {STAGES.map((stage) => {
          const items = getStageItems(stage.value);
          return (
            <Card
              key={stage.value}
              className={`cursor-pointer transition-all ${selectedView === stage.value || (selectedView === "leads" && (stage.value === "demo" || stage.value === "interested")) ? "ring-2 ring-primary" : ""}`}
              onClick={() =>
                changeView(
                  selectedView === stage.value ? null : stage.value
                )
              }
              onDragOver={(e) => e.preventDefault()}
              onDrop={() => handleDrop(stage.value)}
            >
              <CardHeader className="p-3 pb-1">
                <CardTitle className="flex items-center justify-between text-sm">
                  <StatusBadge status={stage.value} />
                  <span className="rounded-full bg-muted px-2 py-0.5 text-xs font-bold">
                    {items.length}
                  </span>
                </CardTitle>
              </CardHeader>
              <CardContent className="max-h-48 space-y-1 overflow-y-auto p-3 pt-1">
                {items.length === 0 ? (
                  <p className="text-xs text-muted-foreground">No items</p>
                ) : (
                  items.slice(0, 5).map((item) => (
                    <div
                      key={item.id}
                      draggable
                      onDragStart={() => setDragItem(item.id)}
                      className="cursor-grab rounded border bg-background p-2 text-xs hover:bg-muted active:cursor-grabbing"
                      onClick={(e) => {
                        e.stopPropagation();
                        router.push(`/onboarding/${item.id}`);
                      }}
                    >
                      <p className="font-medium">{item.schoolName}</p>
                      {item.contactPerson && (
                        <p className="text-muted-foreground">
                          {item.contactPerson}
                        </p>
                      )}
                    </div>
                  ))
                )}
                {items.length > 5 && (
                  <p className="text-xs text-muted-foreground">
                    +{items.length - 5} more
                  </p>
                )}
              </CardContent>
            </Card>
          );
        })}
      </div>

      {/* Filtered Table */}
      <div>
        <h3 className="mb-3 text-lg font-medium">
          {selectedView === "leads"
            ? `Open Leads (${filteredRequests.length})`
            : selectedView
              ? `${STAGES.find((s) => s.value === selectedView)?.label} (${filteredRequests.length})`
            : `All Requests (${requests.length})`}
        </h3>
        <DataTable
          columns={onboardingColumns}
          data={filteredRequests}
          searchKey="schoolName"
          searchPlaceholder="Search by school name..."
          onRowClick={(row) => router.push(`/onboarding/${row.id}`)}
        />
      </div>
    </div>
  );
}
