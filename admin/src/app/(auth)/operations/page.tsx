import Link from "next/link";
import { PageHeader } from "@/components/layout/page-header";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Download, Shield, FileText, Upload, KeyRound, Eye } from "lucide-react";

export default function OperationsPage() {
  const tools = [
    {
      title: "Export Data",
      description: "Download students, reading logs, and allocations as CSV.",
      href: "/operations/export",
      icon: Download,
    },
    {
      title: "Audit Log",
      description: "View admin action history and track all changes.",
      href: "/operations/audit-log",
      icon: FileText,
    },
    {
      title: "Offboard School",
      description: "Deactivate a school and all its data.",
      href: "/operations/offboard",
      icon: Shield,
    },
    {
      title: "Bulk Import",
      description: "Import students from CSV files.",
      href: "/operations/bulk",
      icon: Upload,
    },
    {
      title: "Dev Access",
      description: "Manage emails that can see DEV-only surfaces across the app.",
      href: "/operations/dev-access",
      icon: KeyRound,
    },
    {
      title: "Impersonation Audit",
      description:
        "Review and export developer read-only impersonation sessions.",
      href: "/operations/impersonation-audit",
      icon: Eye,
    },
  ];

  return (
    <>
      <PageHeader
        title="Operations"
        description="Admin tools and data management"
      />
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {tools.map((tool) => (
          <Link
            key={tool.title}
            href={tool.href}
            className=""
          >
            <Card className="h-full transition-colors hover:bg-muted/50">
              <CardHeader className="flex flex-row items-center gap-3">
                <tool.icon className="h-5 w-5 text-muted-foreground" />
                <CardTitle className="text-base">{tool.title}</CardTitle>
              </CardHeader>
              <CardContent>
                <p className="text-sm text-muted-foreground">
                  {tool.description}
                </p>
              </CardContent>
            </Card>
          </Link>
        ))}
      </div>
    </>
  );
}
