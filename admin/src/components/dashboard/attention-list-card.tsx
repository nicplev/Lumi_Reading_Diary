import Link from "next/link";
import {
  AlertCircle,
  AlertTriangle,
  CheckCircle2,
  ChevronRight,
  Info,
} from "lucide-react";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import type { AttentionItem } from "@/lib/dashboard/types";

const SEVERITY_ICONS = {
  error: { icon: AlertCircle, className: "text-red-500" },
  warn: { icon: AlertTriangle, className: "text-amber-500" },
  info: { icon: Info, className: "text-blue-500" },
} as const;

export function AttentionListCard({ items }: { items: AttentionItem[] }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Needs Attention</CardTitle>
      </CardHeader>
      <CardContent>
        {items.length === 0 ? (
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <CheckCircle2 className="h-4 w-4 text-green-500" />
            All clear — nothing needs attention.
          </div>
        ) : (
          <div className="space-y-1">
            {items.map((item) => {
              const { icon: Icon, className } = SEVERITY_ICONS[item.severity];
              return (
                <Link
                  key={item.key}
                  href={item.href}
                  className="flex items-center justify-between gap-2 rounded-md px-2 py-1.5 text-sm hover:bg-muted"
                >
                  <span className="flex min-w-0 items-center gap-2">
                    <Icon className={`h-4 w-4 shrink-0 ${className}`} />
                    <span className="truncate">
                      <span className="font-semibold">{item.count}</span>{" "}
                      {item.label}
                    </span>
                  </span>
                  <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
                </Link>
              );
            })}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
