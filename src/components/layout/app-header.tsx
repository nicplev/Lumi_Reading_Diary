"use client";

import { usePathname } from "next/navigation";
import { SidebarTrigger } from "@/components/ui/sidebar";
import { Separator } from "@/components/ui/separator";
import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbList,
  BreadcrumbPage,
  BreadcrumbSeparator,
} from "@/components/ui/breadcrumb";

const routeLabels: Record<string, string> = {
  "": "Dashboard",
  schools: "Schools",
  classes: "Classes",
  onboarding: "Onboarding",
  "school-codes": "School Codes",
  teachers: "Teachers",
  parents: "Parents",
  students: "Students",
  "reading-logs": "Reading Logs",
  reports: "Reports",
  new: "New",
  library: "Library",
  allocations: "Allocations",
  analytics: "Analytics",
  operations: "Operations",
  export: "Export",
  "link-codes": "Link Codes",
  "audit-log": "Audit Log",
  offboard: "Offboard",
  bulk: "Bulk Import",
};

function getSegmentLabel(segment: string): string {
  if (routeLabels[segment]) return routeLabels[segment];
  // Treat long segments as dynamic IDs (Firebase doc IDs are 20+ chars)
  if (segment.length > 8) return "Details";
  return segment;
}

export function AppHeader() {
  const pathname = usePathname();
  const segments = pathname.split("/").filter(Boolean);

  return (
    <header className="flex h-14 shrink-0 items-center gap-2 border-b px-4">
      <SidebarTrigger />
      <Separator orientation="vertical" className="mr-2 h-4" />
      <Breadcrumb>
        <BreadcrumbList>
          <BreadcrumbItem>
            {segments.length === 0 ? (
              <BreadcrumbPage>Dashboard</BreadcrumbPage>
            ) : (
              <BreadcrumbLink href="/">Dashboard</BreadcrumbLink>
            )}
          </BreadcrumbItem>
          {segments.flatMap((segment, i) => {
            const href = "/" + segments.slice(0, i + 1).join("/");
            const isLast = i === segments.length - 1;
            const label = getSegmentLabel(segment);
            return [
              <BreadcrumbSeparator key={`sep-${href}`} />,
              <BreadcrumbItem key={href}>
                {isLast ? (
                  <BreadcrumbPage>{label}</BreadcrumbPage>
                ) : (
                  <BreadcrumbLink href={href}>{label}</BreadcrumbLink>
                )}
              </BreadcrumbItem>,
            ];
          })}
        </BreadcrumbList>
      </Breadcrumb>
    </header>
  );
}
