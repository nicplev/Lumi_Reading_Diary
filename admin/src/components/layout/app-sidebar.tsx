"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  BookOpen,
  GraduationCap,
  LayoutDashboard,
  Library,
  LogOut,
  MessageSquare,
  School,
  Settings,
  UserPlus,
  Users,
  BarChart3,
  ClipboardList,
  Download,
  Wrench,
  CreditCard,
  FileText,
} from "lucide-react";
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarSeparator,
} from "@/components/ui/sidebar";
import { Button } from "@/components/ui/button";

const navGroups = [
  {
    label: "Overview",
    items: [
      { title: "Dashboard", href: "/", icon: LayoutDashboard },
    ],
  },
  {
    label: "Schools",
    items: [
      { title: "Schools", href: "/schools", icon: School },
      { title: "Classes", href: "/classes", icon: GraduationCap },
    ],
  },
  {
    label: "Onboarding",
    items: [
      { title: "Requests", href: "/onboarding", icon: ClipboardList },
      { title: "School Codes", href: "/school-codes", icon: Settings },
    ],
  },
  {
    label: "Users",
    items: [
      { title: "Teachers", href: "/teachers", icon: Users },
      { title: "Parents", href: "/parents", icon: UserPlus },
      { title: "Students", href: "/students", icon: GraduationCap },
      { title: "Link Codes", href: "/link-codes", icon: Settings },
    ],
  },
  {
    label: "Library",
    items: [
      { title: "Community Books", href: "/community-books", icon: Library },
    ],
  },
  {
    label: "Analytics",
    items: [
      { title: "Overview", href: "/analytics", icon: BarChart3 },
      { title: "Reading Logs", href: "/reading-logs", icon: BookOpen },
    ],
  },
  {
    label: "Operations",
    items: [
      { title: "Operations", href: "/operations", icon: Wrench },
      { title: "Subscriptions", href: "/operations/subscriptions", icon: CreditCard },
      { title: "Invoicing", href: "/operations/invoicing", icon: FileText },
      { title: "Export Data", href: "/operations/export", icon: Download },
    ],
  },
  {
    label: "Support",
    items: [
      { title: "Feedback", href: "/feedback", icon: MessageSquare },
    ],
  },
];

export function AppSidebar() {
  const pathname = usePathname();

  async function handleSignOut() {
    await fetch("/api/auth", { method: "DELETE" });
    window.location.href = "/login";
  }

  return (
    <Sidebar>
      <SidebarHeader>
        <div className="flex items-center gap-2 px-2 py-1">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary text-primary-foreground">
            <BookOpen className="h-4 w-4" />
          </div>
          <div className="flex flex-col">
            <span className="text-sm font-semibold">Lumi Admin</span>
            <span className="text-xs text-muted-foreground">Dashboard</span>
          </div>
        </div>
      </SidebarHeader>
      <SidebarSeparator />
      <SidebarContent>
        {navGroups.map((group) => (
          <SidebarGroup key={group.label}>
            <SidebarGroupLabel>{group.label}</SidebarGroupLabel>
            <SidebarGroupContent>
              <SidebarMenu>
                {group.items.map((item) => (
                  <SidebarMenuItem key={item.href}>
                    <SidebarMenuButton
                      isActive={
                        item.href === "/"
                          ? pathname === "/"
                          : pathname.startsWith(item.href)
                      }
                      render={<Link href={item.href} />}
                      tooltip={item.title}
                    >
                      <item.icon className="h-4 w-4" />
                      <span>{item.title}</span>
                    </SidebarMenuButton>
                  </SidebarMenuItem>
                ))}
              </SidebarMenu>
            </SidebarGroupContent>
          </SidebarGroup>
        ))}
      </SidebarContent>
      <SidebarFooter>
        <SidebarSeparator />
        <div className="p-2">
          <Button
            variant="ghost"
            className="w-full justify-start gap-2"
            onClick={handleSignOut}
          >
            <LogOut className="h-4 w-4" />
            <span>Sign out</span>
          </Button>
        </div>
      </SidebarFooter>
    </Sidebar>
  );
}
