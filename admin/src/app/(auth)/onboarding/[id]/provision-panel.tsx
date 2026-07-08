"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Copy, Rocket } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

interface ProvisionResult {
  schoolId: string;
  inviteLink?: string;
  joinCode?: string;
}

interface ProvisionPanelProps {
  onboardingId: string;
  defaultAdminEmail?: string;
  defaultAdminName?: string;
}

export function ProvisionPanel({
  onboardingId,
  defaultAdminEmail,
  defaultAdminName,
}: ProvisionPanelProps) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [timezone, setTimezone] = useState("Australia/Sydney");
  const [adminEmail, setAdminEmail] = useState(defaultAdminEmail ?? "");
  const [adminFullName, setAdminFullName] = useState(defaultAdminName ?? "");
  const [subscriptionStatus, setSubscriptionStatus] = useState("comp");
  const [createJoinCode, setCreateJoinCode] = useState(false);
  const [result, setResult] = useState<ProvisionResult | null>(null);

  const copy = async (label: string, value: string) => {
    try {
      await navigator.clipboard.writeText(value);
      toast.success(`${label} copied`);
    } catch {
      toast.error("Copy failed");
    }
  };

  const submit = async () => {
    if (!adminEmail.trim() || !adminFullName.trim()) {
      toast.error("Admin name and email are required");
      return;
    }
    setLoading(true);
    try {
      const res = await fetch(`/api/onboarding/${onboardingId}/provision`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          timezone: timezone.trim() || "Australia/Sydney",
          adminEmail: adminEmail.trim(),
          adminFullName: adminFullName.trim(),
          subscriptionStatus,
          createJoinCode,
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "Provision failed");
      setResult({
        schoolId: data.schoolId,
        inviteLink: data.inviteLink,
        joinCode: data.joinCode,
      });
      toast.success("School provisioned — access is switched on");
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Provision failed");
    } finally {
      setLoading(false);
    }
  };

  if (result) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>School provisioned ✓</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4 text-sm">
          <p className="text-muted-foreground">
            The school is created with access switched on for the year.{" "}
            <span className="font-medium text-foreground">
              No email is sent — copy the link below and send it to the admin
              now.
            </span>{" "}
            If you lose it, re-generate it any time from the setup checklist.
          </p>
          {result.inviteLink && (
            <div className="space-y-1">
              <Label className="text-xs">Admin password-setup link</Label>
              <div className="flex gap-2">
                <Input readOnly value={result.inviteLink} className="text-xs" />
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => copy("Invite link", result.inviteLink!)}
                >
                  <Copy className="h-4 w-4" />
                </Button>
              </div>
            </div>
          )}
          {result.joinCode && (
            <div className="space-y-1">
              <Label className="text-xs">Teacher self-join code</Label>
              <div className="flex items-center gap-2">
                <code className="rounded bg-muted px-2 py-1 font-mono text-sm">
                  {result.joinCode}
                </code>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => copy("Join code", result.joinCode!)}
                >
                  <Copy className="h-4 w-4" />
                </Button>
              </div>
            </div>
          )}
          <Button onClick={() => router.refresh()}>Continue to setup</Button>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Provision school</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <p className="text-sm text-muted-foreground">
          Creates the school, switches access on for the year (free comp
          subscription), and creates the school-admin account with a
          password-setup link. Advances the request to Setup In Progress.
        </p>
        <div className="grid gap-3 md:grid-cols-2">
          <div className="space-y-2">
            <Label>Admin name *</Label>
            <Input
              value={adminFullName}
              onChange={(e) => setAdminFullName(e.target.value)}
            />
          </div>
          <div className="space-y-2">
            <Label>Admin email *</Label>
            <Input
              type="email"
              value={adminEmail}
              onChange={(e) => setAdminEmail(e.target.value)}
            />
          </div>
          <div className="space-y-2">
            <Label>Timezone</Label>
            <Input
              value={timezone}
              onChange={(e) => setTimezone(e.target.value)}
            />
          </div>
          <div className="space-y-2">
            <Label>Subscription</Label>
            <Select
              value={subscriptionStatus}
              onValueChange={(v) => v && setSubscriptionStatus(v)}
            >
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="comp">Comp (free)</SelectItem>
                <SelectItem value="trial">Trial</SelectItem>
                <SelectItem value="paid">Paid</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>
        <label className="flex items-center gap-2 text-sm">
          <Switch
            checked={createJoinCode}
            onCheckedChange={(v) => setCreateJoinCode(!!v)}
          />
          Also generate a teacher self-join code
        </label>
        <Button onClick={submit} disabled={loading}>
          <Rocket className="mr-2 h-4 w-4" />
          {loading ? "Provisioning…" : "Provision school"}
        </Button>
      </CardContent>
    </Card>
  );
}
