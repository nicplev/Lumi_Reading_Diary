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
};

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
          {segments.map((segment, i) => {
            const href = "/" + segments.slice(0, i + 1).join("/");
            const isLast = i === segments.length - 1;
            const label = routeLabels[segment] || segment;
            return (
              <BreadcrumbItem key={href}>
                <BreadcrumbSeparator />
                {isLast ? (
                  <BreadcrumbPage>{label}</BreadcrumbPage>
                ) : (
                  <BreadcrumbLink href={href}>{label}</BreadcrumbLink>
                )}
              </BreadcrumbItem>
            );
          })}
        </BreadcrumbList>
      </Breadcrumb>
    </header>
  );
}
