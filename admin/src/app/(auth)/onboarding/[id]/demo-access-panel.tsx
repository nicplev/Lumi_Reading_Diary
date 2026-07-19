"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import {
  CheckCircle2,
  CircleX,
  Copy,
  Eye,
  EyeOff,
  KeyRound,
  LoaderCircle,
  Mail,
  ShieldCheck,
} from "lucide-react";
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
import { DemoFeatureControls } from "@/components/demo/demo-feature-controls";
import type {
  DemoAccessView,
  DemoReadinessView,
} from "@/lib/firestore/demo-access";

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
  const [loading, setLoading] = useState<null | "prepare" | "email">(null);
  const [confirmEmail, setConfirmEmail] = useState(false);
  const [reseedPhase, setReseedPhase] = useState<string | null>(null);
  const [preparePhase, setPreparePhase] = useState<
    "provisioning" | "verifying" | null
  >(null);
  const [readiness, setReadiness] = useState<DemoReadinessView | null>(
    view.readiness,
  );
  // Password from a just-completed provision (avoids a refresh flash); falls
  // back to the server-rendered live password.
  const [freshPassword, setFreshPassword] = useState<string | null>(null);
  const [showPassword, setShowPassword] = useState(false);

  const password = freshPassword ?? view.password;
  const hasLivePassword = !!password;
  const isReadyToday =
    readiness?.ready === true && readiness.dayKey === view.today;

  useEffect(() => {
    if (loading !== "prepare" || preparePhase !== "provisioning") return;

    let cancelled = false;
    const poll = async () => {
      try {
        const response = await fetch("/api/demo/reseed", { cache: "no-store" });
        if (!response.ok) return;
        const status = (await response.json()) as {
          state?: string;
          phase?: string | null;
        };
        if (!cancelled && status.state === "running") {
          setReseedPhase(status.phase ?? "preparing");
        }
      } catch {
        // Provisioning remains authoritative; status polling is best-effort UI.
      }
    };

    void poll();
    const timer = window.setInterval(poll, 1500);
    return () => {
      cancelled = true;
      window.clearInterval(timer);
    };
  }, [loading, preparePhase]);

  const copy = async (label: string, value: string) => {
    try {
      await navigator.clipboard.writeText(value);
      toast.success(`${label} copied`);
    } catch {
      toast.error("Copy failed");
    }
  };

  const prepareAndVerify = async () => {
    const preparationAction = view.active ? "reprovision" : "provision";
    setReseedPhase(null);
    setPreparePhase("provisioning");
    setLoading("prepare");
    try {
      const provisionResponse = await fetch(
        `/api/onboarding/${onboardingId}/demo-access`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ action: preparationAction }),
        },
      );
      const provisionData = await provisionResponse.json();
      if (!provisionResponse.ok) {
        throw new Error(provisionData.error || "Preparation failed");
      }
      setFreshPassword(provisionData.password);
      setPreparePhase("verifying");

      const readinessResponse = await fetch(
        `/api/onboarding/${onboardingId}/demo-readiness`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ confirm: "RUN DEMO PREFLIGHT" }),
        },
      );
      const readinessData = (await readinessResponse.json()) as
        DemoReadinessView & { error?: string };
      if (Array.isArray(readinessData.checks)) {
        setReadiness(readinessData);
      }
      if (!readinessResponse.ok || !readinessData.ready) {
        throw new Error(
          readinessData.error || "The demo is not ready. Review the failed check.",
        );
      }
      toast.success(
        preparationAction === "reprovision"
          ? "Today’s demo was reset, given a new password and verified"
          : "Today’s demo is prepared and verified",
      );
      router.refresh();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Demo preparation failed");
      router.refresh();
    } finally {
      setPreparePhase(null);
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

  const credentialRow = (
    label: string,
    value: string,
    options: { sensitive?: boolean } = {},
  ) => {
    const visibleValue =
      options.sensitive && !showPassword ? "••••••••••••" : value;
    return (
      <div className="space-y-1">
        <Label className="text-xs">{label}</Label>
        <div className="flex items-center gap-2">
          <code className="flex-1 truncate rounded bg-muted px-2 py-1 font-mono text-sm">
            {visibleValue}
          </code>
          {options.sensitive && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => setShowPassword((shown) => !shown)}
              aria-label={
                showPassword ? "Hide shared password" : "Reveal shared password"
              }
            >
              {showPassword ? (
                <EyeOff className="h-4 w-4" />
              ) : (
                <Eye className="h-4 w-4" />
              )}
            </Button>
          )}
          <Button
            variant="outline"
            size="sm"
            onClick={() => copy(label, value)}
            aria-label={`Copy ${label.toLowerCase()}`}
          >
            <Copy className="h-4 w-4" />
          </Button>
        </div>
      </div>
    );
  };

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
            . Prepare and verify it before the call, then read the credentials
            out or email them to the requester. Access self-expires at{" "}
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
              {credentialRow("Shared password (all three logins)", password!, {
                sensitive: true,
              })}
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

          {/* Readiness receipt — deliberately contains no credentials or IDs. */}
          <div
            className={`rounded-lg border p-3 ${
              isReadyToday
                ? "border-emerald-300 bg-emerald-50 text-emerald-950"
                : readiness?.state === "not_ready"
                  ? "border-red-300 bg-red-50 text-red-950"
                  : "border-amber-300 bg-amber-50 text-amber-950"
            }`}
          >
            <div className="flex items-start gap-3">
              {isReadyToday ? (
                <ShieldCheck className="mt-0.5 h-5 w-5 shrink-0" />
              ) : readiness?.state === "not_ready" ? (
                <CircleX className="mt-0.5 h-5 w-5 shrink-0" />
              ) : (
                <ShieldCheck className="mt-0.5 h-5 w-5 shrink-0" />
              )}
              <div className="min-w-0 flex-1">
                <p className="font-medium">
                  {isReadyToday
                    ? "Ready for a customer demo"
                    : readiness?.state === "not_ready"
                      ? "Demo needs attention"
                      : "Demo has not been verified today"}
                </p>
                {readiness?.checkedAtISO && (
                  <p className="mt-0.5 text-xs opacity-75">
                    Checked {fmtSydney(readiness.checkedAtISO)}
                    {readiness.checkedByEmail
                      ? ` by ${readiness.checkedByEmail}`
                      : ""}
                  </p>
                )}
                {readiness?.state === "stale" && (
                  <p className="mt-1 text-xs">
                    Demo data changed after the last check. Prepare and verify it
                    again before presenting.
                  </p>
                )}
              </div>
            </div>
            {readiness && readiness.checks.length > 0 && (
              <ul className="mt-3 space-y-2 border-t border-current/15 pt-3">
                {readiness.checks.map((check) => (
                  <li key={check.key} className="flex items-start gap-2 text-xs">
                    {check.status === "pass" ? (
                      <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0" />
                    ) : check.status === "fail" ? (
                      <CircleX className="mt-0.5 h-4 w-4 shrink-0" />
                    ) : (
                      <LoaderCircle className="mt-0.5 h-4 w-4 shrink-0" />
                    )}
                    <span>
                      <strong>{check.label}:</strong> {check.detail}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </div>

          <DemoFeatureControls
            key={`${view.today}:${view.active}:${view.controls.updatedAtISO ?? "seed"}`}
            initialControls={view.controls}
            active={view.active}
            patchEndpoint={`/api/onboarding/${onboardingId}/demo-controls`}
          />

          {/* Actions */}
          <div className="flex flex-wrap gap-2">
            <Button onClick={prepareAndVerify} disabled={loading !== null}>
              {loading === "prepare" ? (
                <LoaderCircle className="mr-2 h-4 w-4 animate-spin" />
              ) : (
                <ShieldCheck className="mr-2 h-4 w-4" />
              )}
              {loading === "prepare"
                ? preparePhase === "verifying"
                  ? "Verifying live demo…"
                  : view.active
                    ? "Reprovisioning demo…"
                    : "Preparing demo…"
                : view.active
                  ? "Reprovision and check today’s demo"
                  : "Prepare and verify today’s demo"}
            </Button>
            <Button
              variant="outline"
              onClick={() => setConfirmEmail(true)}
              disabled={
                loading !== null ||
                !hasLivePassword ||
                !isReadyToday ||
                !contactEmail
              }
              title={
                !contactEmail
                  ? "This request has no contact email"
                  : !hasLivePassword
                    ? "Prepare today’s demo first"
                    : !isReadyToday
                      ? "The live demo must pass readiness checks before credentials are emailed"
                    : undefined
              }
            >
              <Mail className="mr-2 h-4 w-4" />
              Email demo details
            </Button>
          </div>
          {loading === "prepare" &&
            preparePhase === "provisioning" &&
            reseedPhase && (
              <p className="text-xs text-muted-foreground" role="status">
                Refreshing demo data: {reseedPhase.replaceAll("_", " ")}…
              </p>
            )}

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
