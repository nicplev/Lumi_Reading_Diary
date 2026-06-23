"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { Card, CardContent } from "@/components/ui/card";
import { StatCard } from "@/components/cards/stat-card";
import { StatusBadge } from "@/components/shared/status-badge";
import { Button } from "@/components/ui/button";
import { CheckCircle2, AlertTriangle, School as SchoolIcon } from "lucide-react";
import type { SubscriptionStatus, SubscriptionTier } from "@lumi/types";

export interface BillingRow {
  schoolId: string;
  schoolName: string;
  studentCount: number;
  status: SubscriptionStatus | null;
  tier: SubscriptionTier | null;
  amount: number | null;
  invoiceRef: string | null;
  accessOn: boolean;
}

type Filter = "all" | "paid" | "unpaid";

export function SubscriptionsDashboard({
  rows,
  academicYear,
}: {
  rows: BillingRow[];
  academicYear: number;
}) {
  const [filter, setFilter] = useState<Filter>("all");

  const stats = useMemo(() => {
    const total = rows.length;
    const accessOn = rows.filter((r) => r.accessOn).length;
    return { total, accessOn, suspended: total - accessOn };
  }, [rows]);

  const filtered = useMemo(() => {
    if (filter === "paid") return rows.filter((r) => r.accessOn);
    if (filter === "unpaid") return rows.filter((r) => !r.accessOn);
    return rows;
  }, [rows, filter]);

  return (
    <div className="space-y-6">
      <div className="grid gap-4 md:grid-cols-3">
        <StatCard title="Schools" value={stats.total} icon={SchoolIcon} />
        <StatCard title="Access on" value={stats.accessOn} icon={CheckCircle2} />
        <StatCard
          title="Unpaid / suspended"
          value={stats.suspended}
          icon={AlertTriangle}
        />
      </div>

      <div className="flex gap-2">
        {(["all", "paid", "unpaid"] as Filter[]).map((f) => (
          <Button
            key={f}
            variant={filter === f ? "default" : "outline"}
            size="sm"
            onClick={() => setFilter(f)}
          >
            {f === "all" ? "All" : f === "paid" ? "Access on" : "Unpaid"}
          </Button>
        ))}
      </div>

      <Card>
        <CardContent className="p-0">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b text-left text-muted-foreground">
                <th className="p-3">School</th>
                <th className="p-3">Students</th>
                <th className="p-3">Status</th>
                <th className="p-3">Tier</th>
                <th className="p-3">Amount</th>
                <th className="p-3">Invoice</th>
                <th className="p-3">Access</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((r) => (
                <tr key={r.schoolId} className="border-b last:border-0">
                  <td className="p-3 font-medium">
                    <Link
                      href={`/schools/${r.schoolId}?tab=subscription`}
                      className="hover:underline"
                    >
                      {r.schoolName}
                    </Link>
                  </td>
                  <td className="p-3">{r.studentCount}</td>
                  <td className="p-3">{r.status ?? "— none —"}</td>
                  <td className="p-3">{r.tier ?? "—"}</td>
                  <td className="p-3">{r.amount != null ? `$${r.amount}` : "—"}</td>
                  <td className="p-3 text-muted-foreground">
                    {r.invoiceRef ?? "—"}
                  </td>
                  <td className="p-3">
                    <StatusBadge status={r.accessOn ? "active" : "suspended"} />
                  </td>
                </tr>
              ))}
              {filtered.length === 0 && (
                <tr>
                  <td colSpan={7} className="p-6 text-center text-muted-foreground">
                    No schools match this filter for {academicYear}.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </CardContent>
      </Card>
    </div>
  );
}
