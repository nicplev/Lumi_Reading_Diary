"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { formatDateTime } from "@/lib/utils";
import { ChevronLeft, Download, Shield, AlertTriangle } from "lucide-react";
import type {
  ImpersonationAuditEvent,
  ImpersonationSession,
} from "@/lib/firestore/impersonation-audit";

interface Props {
  initialSession: ImpersonationSession;
  initialEvents: ImpersonationAuditEvent[];
}

function eventBadgeColor(t: ImpersonationAuditEvent["eventType"]): string {
  switch (t) {
    case "session_started":
      return "bg-blue-100 text-blue-900";
    case "session_ended":
      return "bg-gray-100 text-gray-800";
    case "session_expired":
      return "bg-amber-100 text-amber-900";
    case "session_revoked":
      return "bg-red-100 text-red-900";
    case "write_blocked_client":
      return "bg-red-50 text-red-800";
    case "audit_exported":
      return "bg-purple-100 text-purple-900";
    case "screen_viewed":
      return "bg-slate-100 text-slate-800";
    default:
      return "bg-gray-100 text-gray-800";
  }
}

function statusBadgeColor(status: ImpersonationSession["status"]): string {
  switch (status) {
    case "active":
      return "bg-green-100 text-green-900";
    case "revoked":
      return "bg-red-100 text-red-900";
    case "expired":
      return "bg-amber-100 text-amber-900";
    case "ended":
    default:
      return "bg-gray-100 text-gray-800";
  }
}

export function SessionDetailView({ initialSession, initialEvents }: Props) {
  const router = useRouter();
  const [session, setSession] = useState(initialSession);
  const [events, setEvents] = useState(initialEvents);
  const [revokeOpen, setRevokeOpen] = useState(false);
  const [revokeReason, setRevokeReason] = useState("");
  const [revoking, setRevoking] = useState(false);
  const [exporting, setExporting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleRevoke = async () => {
    if (revokeReason.trim().length < 5) {
      setError("Reason must be at least 5 characters.");
      return;
    }
    setRevoking(true);
    setError(null);
    try {
      const res = await fetch(
        `/api/impersonation-audit/sessions/${session.id}/revoke`,
        {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ reason: revokeReason.trim() }),
        },
      );
      const body = await res.json();
      if (!res.ok) throw new Error(body.error ?? `HTTP ${res.status}`);
      setSession(body.session);
      // Pull the fresh events list (includes the new revoked event).
      const evRes = await fetch(
        `/api/impersonation-audit/sessions/${session.id}/events`,
      );
      if (evRes.ok) {
        const evBody = await evRes.json();
        setEvents(evBody.events ?? []);
      }
      setRevokeOpen(false);
      setRevokeReason("");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Revoke failed.");
    } finally {
      setRevoking(false);
    }
  };

  const handleExport = async () => {
    setExporting(true);
    setError(null);
    try {
      const res = await fetch(
        `/api/impersonation-audit/sessions/${session.id}/export`,
      );
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.error ?? `HTTP ${res.status}`);
      }
      // csv-export-guardrail: pass-through — the server already encoded this
      // CSV with toCsvString (formula-safe); re-encoding here would double it.
      const text = await res.text();
      const blob = new Blob([text], { type: "text/csv;charset=utf-8" });
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = `impersonation-${session.id}.csv`;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      URL.revokeObjectURL(url);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Export failed.");
    } finally {
      setExporting(false);
    }
  };

  return (
    <div className="space-y-6">
      <div>
        <Button
          variant="ghost"
          size="sm"
          onClick={() => router.push("/operations/impersonation-audit")}
          className="gap-2"
        >
          <ChevronLeft className="h-4 w-4" /> Back to audit
        </Button>
      </div>

      <Card>
        <CardHeader className="flex flex-row items-start justify-between gap-4">
          <div>
            <CardTitle className="flex items-center gap-3">
              <span>{session.targetSchoolName ?? session.targetSchoolId}</span>
              <span
                className={`rounded-full px-2 py-0.5 text-xs font-semibold ${statusBadgeColor(session.status)}`}
              >
                {session.status}
              </span>
            </CardTitle>
            <p className="mt-1 text-sm text-muted-foreground">
              {session.devEmail} · as {session.targetRole} ·{" "}
              {formatDateTime(session.startedAt)}
            </p>
          </div>
          <div className="flex gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={handleExport}
              disabled={exporting}
              className="gap-2"
            >
              <Download className="h-4 w-4" />
              {exporting ? "Exporting…" : "Export CSV"}
            </Button>
            {session.status === "active" && (
              <Button
                variant="destructive"
                size="sm"
                onClick={() => setRevokeOpen(true)}
                className="gap-2"
              >
                <Shield className="h-4 w-4" /> Revoke now
              </Button>
            )}
          </div>
        </CardHeader>
        <CardContent>
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Session ID" value={session.id} mono />
            <Field
              label="Target user"
              value={session.targetUserEmail ?? session.targetUserId}
            />
            <Field label="Target school ID" value={session.targetSchoolId} mono />
            <Field label="Target user ID" value={session.targetUserId} mono />
            <Field
              label="Started"
              value={formatDateTime(session.startedAt)}
            />
            <Field label="Expires" value={formatDateTime(session.expiresAt)} />
            {session.endedAt && (
              <Field label="Ended" value={formatDateTime(session.endedAt)} />
            )}
            {session.endReason && (
              <Field label="End reason" value={session.endReason} />
            )}
          </div>
          <div className="mt-6">
            <p className="text-sm font-semibold text-muted-foreground">
              Developer-supplied reason
            </p>
            <p className="mt-1 rounded-md border bg-muted/40 p-3 text-sm whitespace-pre-wrap">
              {session.reason || "—"}
            </p>
          </div>
          {session.clientInfo && Object.keys(session.clientInfo).length > 0 && (
            <div className="mt-4">
              <p className="text-sm font-semibold text-muted-foreground">
                Client info
              </p>
              <pre className="mt-1 overflow-auto rounded-md bg-muted p-3 text-xs">
                {JSON.stringify(session.clientInfo, null, 2)}
              </pre>
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Timeline</CardTitle>
          <p className="text-xs text-muted-foreground">
            {events.length} event{events.length === 1 ? "" : "s"}
          </p>
        </CardHeader>
        <CardContent>
          {events.length === 0 ? (
            <p className="text-sm text-muted-foreground">No events recorded.</p>
          ) : (
            <ol className="space-y-2">
              {events.map((e) => (
                <li
                  key={e.id}
                  className="flex items-start gap-3 rounded-md border p-3"
                >
                  <span
                    className={`rounded px-2 py-0.5 text-[11px] font-semibold ${eventBadgeColor(e.eventType)}`}
                  >
                    {e.eventType}
                  </span>
                  <div className="flex-1 min-w-0">
                    <p className="text-xs text-muted-foreground">
                      {formatDateTime(e.timestamp)}
                    </p>
                    {Object.keys(e.details).length > 0 && (
                      <pre className="mt-1 overflow-auto rounded bg-muted/40 p-2 text-[11px]">
                        {JSON.stringify(e.details, null, 2)}
                      </pre>
                    )}
                  </div>
                </li>
              ))}
            </ol>
          )}
        </CardContent>
      </Card>

      {error && (
        <div className="flex items-center gap-2 rounded-md border border-red-300 bg-red-50 p-3 text-sm text-red-800">
          <AlertTriangle className="h-4 w-4" />
          {error}
        </div>
      )}

      <div className="text-xs text-muted-foreground">
        <Link
          href="/operations/impersonation-audit"
          className="underline-offset-4 hover:underline"
        >
          ← Back to list
        </Link>
      </div>

      <Dialog
        open={revokeOpen}
        onOpenChange={(open) => {
          if (!open) {
            setRevokeOpen(false);
            setRevokeReason("");
            setError(null);
          }
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Revoke impersonation session?</DialogTitle>
            <DialogDescription>
              This kills the dev&apos;s active session immediately. The client
              will detect the change within a few seconds and sign out. A
              revocation event is added to the audit trail.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2 py-2">
            <Label>Reason for revocation (≥ 5 chars)</Label>
            <Input
              value={revokeReason}
              onChange={(e) => setRevokeReason(e.target.value)}
              placeholder="e.g. Session started for the wrong school"
              autoFocus
            />
            {error && <p className="text-xs text-red-600">{error}</p>}
          </div>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setRevokeOpen(false)}
              disabled={revoking}
            >
              Cancel
            </Button>
            <Button
              variant="destructive"
              onClick={handleRevoke}
              disabled={revoking || revokeReason.trim().length < 5}
            >
              {revoking ? "Revoking…" : "Revoke"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

function Field({
  label,
  value,
  mono,
}: {
  label: string;
  value: string;
  mono?: boolean;
}) {
  return (
    <div>
      <p className="text-xs font-semibold text-muted-foreground">{label}</p>
      <p className={`text-sm ${mono ? "font-mono break-all" : ""}`}>{value}</p>
    </div>
  );
}
