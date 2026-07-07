"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { ArrowRight, RefreshCw, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import type { OnboardingDetail } from "@/lib/firestore/onboarding";

const STATUSES = [
  { value: "demo", label: "Demo" },
  { value: "interested", label: "Interested" },
  { value: "registered", label: "Registered" },
  { value: "setupInProgress", label: "Setup In Progress" },
  { value: "active", label: "Active" },
  { value: "suspended", label: "Suspended" },
];

interface OnboardingActionsProps {
  onboarding: OnboardingDetail;
}

export function OnboardingActions({ onboarding }: OnboardingActionsProps) {
  const router = useRouter();
  const [loading, setLoading] = useState<string | null>(null);
  const [newStatus, setNewStatus] = useState(onboarding.status);
  const [confirmDelete, setConfirmDelete] = useState(false);

  const performAction = async (
    body: Record<string, string>,
    actionName: string
  ) => {
    setLoading(actionName);
    try {
      const res = await fetch(`/api/onboarding/${onboarding.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "Action failed");
      router.refresh();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Action failed");
    } finally {
      setLoading(null);
    }
  };

  const runDelete = async () => {
    setLoading("delete");
    try {
      const res = await fetch(`/api/onboarding/${onboarding.id}`, {
        method: "DELETE",
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "Delete failed");
      toast.success("Request deleted");
      router.push("/onboarding");
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Delete failed");
      setLoading(null);
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Actions</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex flex-wrap items-end gap-4">
          <Button
            onClick={() => performAction({ action: "advanceStep" }, "advance")}
            disabled={
              loading !== null || onboarding.currentStep === "completed"
            }
          >
            {loading === "advance" ? (
              <RefreshCw className="mr-2 h-4 w-4 animate-spin" />
            ) : (
              <ArrowRight className="mr-2 h-4 w-4" />
            )}
            Advance Step
          </Button>

          <div className="flex items-end gap-2">
            <div className="space-y-1">
              <Label className="text-xs">Change Status</Label>
              <Select
                value={newStatus}
                onValueChange={(v) => v && setNewStatus(v)}
              >
                <SelectTrigger className="w-[180px]">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {STATUSES.map((s) => (
                    <SelectItem key={s.value} value={s.value}>
                      {s.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <Button
              variant="outline"
              onClick={() =>
                performAction(
                  { action: "updateStatus", status: newStatus },
                  "status"
                )
              }
              disabled={loading !== null || newStatus === onboarding.status}
            >
              Update
            </Button>
          </div>

          <Button
            variant="ghost"
            className="text-destructive"
            onClick={() => setConfirmDelete(true)}
            disabled={loading !== null}
          >
            <Trash2 className="mr-2 h-4 w-4" />
            Delete
          </Button>
        </div>
      </CardContent>

      <ConfirmDialog
        open={confirmDelete}
        onOpenChange={setConfirmDelete}
        title="Delete onboarding request"
        description={`Permanently remove the request for ${onboarding.schoolName}? This does not touch any provisioned school — only the pipeline record.`}
        confirmLabel="Delete"
        variant="destructive"
        onConfirm={runDelete}
        loading={loading === "delete"}
      />
    </Card>
  );
}
