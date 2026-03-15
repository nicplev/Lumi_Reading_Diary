import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";

const statusStyles: Record<string, string> = {
  active: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200",
  completed: "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200",
  pending: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200",
  expired: "bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200",
  revoked: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200",
  used: "bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200",
  suspended: "bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200",
  failed: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200",
  demo: "bg-cyan-100 text-cyan-800 dark:bg-cyan-900 dark:text-cyan-200",
  interested: "bg-indigo-100 text-indigo-800 dark:bg-indigo-900 dark:text-indigo-200",
  registered: "bg-teal-100 text-teal-800 dark:bg-teal-900 dark:text-teal-200",
  setupInProgress: "bg-amber-100 text-amber-800 dark:bg-amber-900 dark:text-amber-200",
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
      {status.replace(/([A-Z])/g, " $1").trim()}
    </Badge>
  );
}
