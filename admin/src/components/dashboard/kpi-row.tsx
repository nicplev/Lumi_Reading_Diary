import { School, Users, BookOpen, Activity, Flame } from "lucide-react";
import { StatCard } from "@/components/cards/stat-card";
import type { DashboardKpis } from "@/lib/dashboard/types";

function weekDelta(kpis: DashboardKpis) {
  if (kpis.logsLastWeek === 0) {
    return kpis.logsThisWeek > 0
      ? { label: "no logs in prior 7 days", direction: "up" as const }
      : undefined;
  }
  const pct = Math.round(
    ((kpis.logsThisWeek - kpis.logsLastWeek) / kpis.logsLastWeek) * 100
  );
  return {
    label: `${pct >= 0 ? "+" : ""}${pct}% vs prior 7 days`,
    direction: pct > 0 ? ("up" as const) : pct < 0 ? ("down" as const) : ("flat" as const),
  };
}

export function KpiRow({ kpis }: { kpis: DashboardKpis }) {
  return (
    <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-5">
      <StatCard
        title="Active Schools"
        value={kpis.activeSchools}
        icon={School}
        description={`${kpis.onboardingInProgress} in onboarding pipeline`}
      />
      <StatCard
        title="Active Students"
        value={kpis.activeStudents}
        icon={Users}
      />
      <StatCard
        title="Logs Today"
        value={kpis.logsToday}
        icon={Flame}
        description="Sydney calendar day"
      />
      <StatCard
        title="Logs This Week"
        value={kpis.logsThisWeek}
        icon={BookOpen}
        delta={weekDelta(kpis)}
      />
      <StatCard
        title="Active Readers (7d)"
        value={kpis.weeklyActiveStudents}
        icon={Activity}
        description="Students with ≥1 log"
      />
    </div>
  );
}
