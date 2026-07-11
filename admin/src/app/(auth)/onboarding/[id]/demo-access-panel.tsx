"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Copy, KeyRound, Mail } from "lucide-react";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { StatusBadge } from "@/components/shared/status-badge";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import type { DemoAccessView } from "@/lib/firestore/demo-access";

interface DemoAccessPanelProps {
  onboardingId: string;
  contactEmail: string;
  view: DemoAccessView;
}

function fmtSydney(iso: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (isNaN(d.getTime())) return "—";
  return new Intl.DateTimeFormat("en-AU", {
    timeZone: "Australia/Sydney",
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
    hour12: true,
  }).format(d);
}

export function DemoAccessPanel({
  onboardingId,
  contactEmail,
  view,
}: DemoAccessPanelProps) {
  const router = useRouter();
  const [loading, setLoading] = useState<null | "provision" | "email">(null);
  const [confirmEmail, setConfirmEmail] = useState(false);
  // Password from a just-completed provision (avoids a refresh flash); falls
  // back to the server-rendered live password.
  const [freshPassword, setFreshPassword] = useState<string | null>(null);

  const password = freshPassword ?? view.password;
  const hasLivePassword = !!password;

  const copy = async (label: string, value: string) => {
    try {
      await navigator.clipboard.writeText(value);
      toast.success(`${label} copied`);
    } catch {
      toast.error("Copy failed");
    }
  };

  const provision = async () => {
    setLoading("provision");
    try {
      const res = await fetch(`/api/onboarding/${onboardingId}/demo-access`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "provision" }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "Provision failed");
      setFreshPassword(data.password);
      toast.success(
        data.reused
          ? "Reused today's demo password"
          : "Today's demo password is live"
      );
      router.refresh();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Provision failed");
    } finally {
      setLoading(null);
    }
  };

  const sendEmail = async () => {
    setLoading("email");
    try {
      const res = await fetch(`/api/onboarding/${onboardingId}/demo-access`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "sendEmail" }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "Send failed");
      toast.success(`Demo details emailed to ${data.to}`);
      setConfirmEmail(false);
      router.refresh();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Send failed");
    } finally {
      setLoading(null);
    }
  };

  const credentialRow = (label: string, value: string) => (
    <div className="space-y-1">
      <Label className="text-xs">{label}</Label>
      <div className="flex items-center gap-2">
        <code className="flex-1 truncate rounded bg-muted px-2 py-1 font-mono text-sm">
          {value}
        </code>
        <Button
          variant="outline"
          size="sm"
          onClick={() => copy(label, value)}
        >
          <Copy className="h-4 w-4" />
        </Button>
      </div>
    </div>
  );

  return (
    <>
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <KeyRound className="h-4 w-4" />
            Demo access
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4 text-sm">
          <p className="text-muted-foreground">
            Demos run on the shared Lumi Demo school with a{" "}
            <span className="font-medium text-foreground">
              rolling daily password
            </span>
            . Provision it, then read the credentials out on the call or email
            them to the requester. Access self-expires at{" "}
            <span className="font-medium text-foreground">
              midnight (Sydney)
            </span>
            .
          </p>

          {/* Status */}
          <div className="flex items-center gap-2">
            {hasLivePassword ? (
              <>
                <StatusBadge status="active" />
                <span className="text-muted-foreground">
                  Issued {fmtSydney(view.issuedAtISO)}
                  {view.issuedByEmail ? ` by ${view.issuedByEmail}` : ""} ·
                  expires midnight tonight
                </span>
              </>
            ) : view.scrambled ? (
              <span className="text-muted-foreground">
                Today&apos;s password has expired — provision again for a fresh
                one.
              </span>
            ) : (
              <span className="text-muted-foreground">
                No password issued for today yet.
              </span>
            )}
          </div>

          {/* Credentials */}
          {hasLivePassword && (
            <div className="space-y-3 rounded-lg border p-3">
              {credentialRow("Shared password (all three logins)", password!)}
              <div className="grid gap-3 sm:grid-cols-3">
                {credentialRow("Admin portal", view.adminEmail)}
                {credentialRow("Teacher (app)", view.teacherEmail)}
                {credentialRow("Parent (app)", view.parentEmail)}
              </div>
              <p className="text-xs text-muted-foreground">
                Portal login:{" "}
                <a
                  href={view.portalLoginUrl}
                  target="_blank"
                  rel="noreferrer"
                  className="underline"
                >
                  {view.portalLoginUrl}
                </a>
              </p>
            </div>
          )}

          {/* Actions */}
          <div className="flex flex-wrap gap-2">
            <Button onClick={provision} disabled={loading !== null}>
              <KeyRound className="mr-2 h-4 w-4" />
              {loading === "provision"
                ? "Provisioning…"
                : hasLivePassword
                  ? "Re-issue today's password"
                  : "Provision today's demo password"}
            </Button>
            <Button
              variant="outline"
              onClick={() => setConfirmEmail(true)}
              disabled={loading !== null || !hasLivePassword || !contactEmail}
              title={
                !contactEmail
                  ? "This request has no contact email"
                  : !hasLivePassword
                    ? "Provision today's password first"
                    : undefined
              }
            >
              <Mail className="mr-2 h-4 w-4" />
              Email demo details
            </Button>
          </div>

          {/* Send history for this request */}
          {view.history.length > 0 && (
            <div className="space-y-2">
              <Label className="text-xs">Demo emails sent for this request</Label>
              <ul className="space-y-1 text-xs text-muted-foreground">
                {view.history.map((h) => (
                  <li key={h.id} className="flex items-center gap-2">
                    <StatusBadge status={h.status} />
                    <span>{h.to}</span>
                    <span>·</span>
                    <span>{fmtSydney(h.sentAtISO || h.createdAtISO)}</span>
                    {h.error && (
                      <span className="text-destructive">· {h.error}</span>
                    )}
                  </li>
                ))}
              </ul>
            </div>
          )}
        </CardContent>
      </Card>

      <ConfirmDialog
        open={confirmEmail}
        onOpenChange={setConfirmEmail}
        title="Email demo details"
        description={`Send today's demo credentials and login instructions to ${contactEmail}? A copy is BCC'd to support@lumi-reading.com.`}
        confirmLabel="Send email"
        onConfirm={sendEmail}
        loading={loading === "email"}
      />
    </>
  );
}
