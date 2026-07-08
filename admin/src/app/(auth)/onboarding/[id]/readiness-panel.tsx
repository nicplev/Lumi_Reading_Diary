"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { toast } from "sonner";
import { Check, AlertTriangle, X, Minus, Rocket, Copy } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import { cn } from "@/lib/utils";
import type {
  OnboardingReadiness,
  ReadinessItem,
} from "@/lib/firestore/onboarding";

function StatusIcon({ status }: { status: ReadinessItem["status"] }) {
  const cls = "h-4 w-4 shrink-0";
  if (status === "ok") return <Check className={cn(cls, "text-green-600")} />;
  if (status === "warn")
    return <AlertTriangle className={cn(cls, "text-amber-500")} />;
  if (status === "fail") return <X className={cn(cls, "text-destructive")} />;
  return <Minus className={cn(cls, "text-muted-foreground")} />;
}

interface ReadinessPanelProps {
  onboardingId: string;
  schoolId: string;
  readiness: OnboardingReadiness;
  isActive: boolean;
}

export function ReadinessPanel({
  onboardingId,
  schoolId,
  readiness,
  isActive,
}: ReadinessPanelProps) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [adminLinkLoading, setAdminLinkLoading] = useState(false);

  const warnings = readiness.items.filter(
    (i) => !i.blocking && i.status === "warn"
  );

  const copyAdminLink = async () => {
    setAdminLinkLoading(true);
    try {
      const res = await fetch(`/api/onboarding/${onboardingId}/admin-link`, {
        method: "POST",
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "Failed to generate link");
      try {
        await navigator.clipboard.writeText(data.link);
        toast.success(`Setup link copied — send it to ${data.email}`);
      } catch {
        toast.success(`Setup link for ${data.email}`, {
          description: data.link,
        });
      }
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to generate link");
    } finally {
      setAdminLinkLoading(false);
    }
  };

  const runGoLive = async () => {
    setLoading(true);
    try {
      const res = await fetch(`/api/onboarding/${onboardingId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "goLive" }),
      });
      const data = await res.json();
      if (!res.ok) {
        throw new Error(
          data.blockers
            ? `Not ready: ${data.blockers.join(", ")}`
            : data.error || "Go live failed"
        );
      }
      toast.success(
        data.provisioned > 0
          ? `School is live — granted access to ${data.provisioned} student(s)`
          : "School is live"
      );
      setConfirmOpen(false);
      router.refresh();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Go live failed");
    } finally {
      setLoading(false);
    }
  };

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle>Setup readiness</CardTitle>
        <Link
          href={`/schools/${schoolId}`}
          className="text-sm text-primary hover:underline"
        >
          Open school →
        </Link>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex items-center justify-between gap-3 rounded-md border bg-muted/40 p-3">
          <div className="text-sm">
            <p className="font-medium">Admin access</p>
            <p className="text-xs text-muted-foreground">
              No email is sent automatically — copy this link and send it to the
              admin so they can set their password.
            </p>
          </div>
          <Button
            variant="outline"
            size="sm"
            onClick={copyAdminLink}
            disabled={adminLinkLoading}
          >
            <Copy className="mr-2 h-4 w-4" />
            {adminLinkLoading ? "Generating…" : "Copy admin setup link"}
          </Button>
        </div>

        <ul className="space-y-2">
          {readiness.items.map((item) => (
            <li key={item.key} className="flex items-start gap-2 text-sm">
              <StatusIcon status={item.status} />
              <div className="flex-1">
                <span
                  className={cn(
                    "font-medium",
                    item.status === "fail" && item.blocking && "text-destructive"
                  )}
                >
                  {item.label}
                </span>
                <span className="text-muted-foreground"> — {item.detail}</span>
                {item.blocking && (
                  <span className="ml-1 text-xs text-muted-foreground">
                    (required)
                  </span>
                )}
              </div>
              {item.fixHref && item.status !== "ok" && item.status !== "na" && (
                <Link
                  href={item.fixHref}
                  className="text-xs text-primary hover:underline"
                >
                  Fix
                </Link>
              )}
            </li>
          ))}
        </ul>

        {isActive ? (
          <p className="text-sm font-medium text-green-600">
            This school is live. 🎉
          </p>
        ) : (
          <div className="flex items-center gap-3">
            <Button
              onClick={() => setConfirmOpen(true)}
              disabled={!readiness.canGoLive || loading}
            >
              <Rocket className="mr-2 h-4 w-4" />
              Go Live
            </Button>
            {!readiness.canGoLive && (
              <span className="text-sm text-muted-foreground">
                Resolve the required items first.
              </span>
            )}
          </div>
        )}
      </CardContent>

      <ConfirmDialog
        open={confirmOpen}
        onOpenChange={setConfirmOpen}
        title="Take this school live?"
        description={
          warnings.length > 0
            ? `${warnings.length} recommended item(s) are still open: ${warnings
                .map((w) => w.label)
                .join(", ")}. Go Live will still grant access to any imported students. Proceed anyway?`
            : "Marks the request Active and grants access to any imported-but-unprovisioned students."
        }
        confirmLabel="Go Live"
        onConfirm={runGoLive}
        loading={loading}
      />
    </Card>
  );
}
