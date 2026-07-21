import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";

const statusStyles: Record<string, string> = {
  new: "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200",
  reviewed: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200",
  resolved: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200",
  bug: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200",
  featureRequest: "bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200",
  general: "bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200",
  parent: "bg-teal-100 text-teal-800 dark:bg-teal-900 dark:text-teal-200",
  active: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200",
  completed: "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200",
  pending: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200",
  expired: "bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200",
  revoked: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200",
  used: "bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200",
  suspended: "bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200",
  approved: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200",
  rejected: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200",
  failed: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200",
  demo: "bg-cyan-100 text-cyan-800 dark:bg-cyan-900 dark:text-cyan-200",
  interested: "bg-indigo-100 text-indigo-800 dark:bg-indigo-900 dark:text-indigo-200",
  registered: "bg-teal-100 text-teal-800 dark:bg-teal-900 dark:text-teal-200",
  setupInProgress: "bg-amber-100 text-amber-800 dark:bg-amber-900 dark:text-amber-200",
  disabled: "bg-gray-100 text-red-800 dark:bg-gray-900 dark:text-red-200",
  linked: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200",
  unlinked: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200",
  teacher: "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200",
  schoolAdmin: "bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200",
  byLevel: "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200",
  byTitle: "bg-indigo-100 text-indigo-800 dark:bg-indigo-900 dark:text-indigo-200",
  freeChoice: "bg-emerald-100 text-emerald-800 dark:bg-emerald-900 dark:text-emerald-200",
  partial: "bg-amber-100 text-amber-800 dark:bg-amber-900 dark:text-amber-200",
  skipped: "bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200",
  hard: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200",
  tricky: "bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200",
  okay: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200",
  good: "bg-lime-100 text-lime-800 dark:bg-lime-900 dark:text-lime-200",
  great: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200",
  popular: "bg-pink-100 text-pink-800 dark:bg-pink-900 dark:text-pink-200",
  open: "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200",
  acknowledged: "bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200",
  retried: "bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200",
  processing: "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200",
  retrying: "bg-amber-100 text-amber-800 dark:bg-amber-900 dark:text-amber-200",
  "cooling-off": "bg-cyan-100 text-cyan-800 dark:bg-cyan-900 dark:text-cyan-200",
  "manual-review": "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200",
};

interface StatusBadgeProps {
  status: string;
  className?: string;
}

export function StatusBadge({ status, className }: StatusBadgeProps) {
  return (
    <Badge
      variant="outline"
      className={cn(
        "border-transparent font-medium capitalize",
        statusStyles[status] || "bg-muted text-muted-foreground",
        className
      )}
    >
      {status.replace(/-/g, " ").replace(/([A-Z])/g, " $1").trim()}
    </Badge>
  );
}
