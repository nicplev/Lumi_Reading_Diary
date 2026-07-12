import type { LucideIcon } from "lucide-react";
import { TrendingDown, TrendingUp, Minus } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { cn } from "@/lib/utils";

interface StatCardDelta {
  label: string;
  direction: "up" | "down" | "flat";
}

interface StatCardProps {
  title: string;
  value: string | number;
  description?: string;
  icon?: LucideIcon;
  delta?: StatCardDelta;
}

const deltaIcons = {
  up: TrendingUp,
  down: TrendingDown,
  flat: Minus,
} as const;

export function StatCard({
  title,
  value,
  description,
  icon: Icon,
  delta,
}: StatCardProps) {
  const DeltaIcon = delta ? deltaIcons[delta.direction] : null;
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium">{title}</CardTitle>
        {Icon && <Icon className="h-4 w-4 text-muted-foreground" />}
      </CardHeader>
      <CardContent>
        <div className="text-2xl font-bold">{value}</div>
        {description && (
          <p className="text-xs text-muted-foreground">{description}</p>
        )}
        {delta && DeltaIcon && (
          <p
            className={cn(
              "mt-1 flex items-center gap-1 text-xs",
              delta.direction === "up" && "text-green-600 dark:text-green-400",
              delta.direction === "down" && "text-red-600 dark:text-red-400",
              delta.direction === "flat" && "text-muted-foreground"
            )}
          >
            <DeltaIcon className="h-3 w-3" />
            {delta.label}
          </p>
        )}
      </CardContent>
    </Card>
  );
}
