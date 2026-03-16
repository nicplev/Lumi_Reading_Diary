"use client";

import { useRouter } from "next/navigation";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { DataTable } from "@/components/data-table/data-table";
import type { OnboardingListItem } from "@/lib/firestore/onboarding";
import { onboardingColumns } from "./onboarding-columns";

const STATUSES = [
  { value: "all", label: "All" },
  { value: "demo", label: "Demo" },
  { value: "interested", label: "Interested" },
  { value: "registered", label: "Registered" },
  { value: "setupInProgress", label: "Setup" },
  { value: "active", label: "Active" },
  { value: "suspended", label: "Suspended" },
];

interface OnboardingPipelineProps {
  requests: OnboardingListItem[];
}

export function OnboardingPipeline({ requests }: OnboardingPipelineProps) {
  const router = useRouter();

  const getCount = (status: string) => {
    if (status === "all") return requests.length;
    return requests.filter((r) => r.status === status).length;
  };

  const getFiltered = (status: string) => {
    if (status === "all") return requests;
    return requests.filter((r) => r.status === status);
  };

  return (
    <Tabs defaultValue="all" className="space-y-4">
      <TabsList className="flex-wrap">
        {STATUSES.map((s) => (
          <TabsTrigger key={s.value} value={s.value}>
            {s.label}
            <span className="ml-1.5 rounded-full bg-muted px-2 py-0.5 text-xs font-medium">
              {getCount(s.value)}
            </span>
          </TabsTrigger>
        ))}
      </TabsList>
      {STATUSES.map((s) => (
        <TabsContent key={s.value} value={s.value}>
          <DataTable
            columns={onboardingColumns}
            data={getFiltered(s.value)}
            searchKey="schoolName"
            searchPlaceholder="Search by school name..."
            onRowClick={(row) => router.push(`/onboarding/${row.id}`)}
          />
        </TabsContent>
      ))}
    </Tabs>
  );
}
