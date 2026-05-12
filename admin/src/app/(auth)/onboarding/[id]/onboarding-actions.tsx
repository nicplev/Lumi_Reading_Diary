"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { ArrowRight, Link2, RefreshCw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
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
  const [error, setError] = useState<string | null>(null);
  const [newStatus, setNewStatus] = useState(onboarding.status);
  const [schoolId, setSchoolId] = useState("");

  const performAction = async (
    body: Record<string, string>,
    actionName: string
  ) => {
    setLoading(actionName);
    setError(null);

    try {
      const res = await fetch(`/api/onboarding/${onboarding.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });

      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || "Action failed");
      }

      router.refresh();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(null);
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Actions</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        {error && (
          <div className="rounded-md bg-destructive/10 p-3 text-sm text-destructive">
            {error}
          </div>
        )}

        <div className="flex flex-wrap gap-4">
          <Button
            onClick={() =>
              performAction({ action: "advanceStep" }, "advance")
            }
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
              <Select value={newStatus} onValueChange={(v) => v && setNewStatus(v)}>
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

          {!onboarding.schoolId && (
            <div className="flex items-end gap-2">
              <div className="space-y-1">
                <Label className="text-xs">Link to School</Label>
                <Input
                  placeholder="School ID"
                  value={schoolId}
                  onChange={(e) => setSchoolId(e.target.value)}
                  className="w-[200px]"
                />
              </div>
              <Button
                variant="outline"
                onClick={() =>
                  performAction(
                    { action: "linkSchool", schoolId },
                    "link"
                  )
                }
                disabled={loading !== null || !schoolId}
              >
                <Link2 className="mr-2 h-4 w-4" />
                Link
              </Button>
            </div>
          )}
        </div>
      </CardContent>
    </Card>
  );
}
