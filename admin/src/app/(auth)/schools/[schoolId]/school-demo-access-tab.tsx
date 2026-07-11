import Link from "next/link";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { StatusBadge } from "@/components/shared/status-badge";
import type { DemoEmailHistoryItem } from "@/lib/firestore/demo-access";

function fmtSydney(iso: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (isNaN(d.getTime())) return "—";
  return new Intl.DateTimeFormat("en-AU", {
    timeZone: "Australia/Sydney",
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: true,
  }).format(d);
}

export function SchoolDemoAccessTab({
  emails,
}: {
  emails: DemoEmailHistoryItem[];
}) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Demo access emails</CardTitle>
        <CardDescription>
          Everyone who has been sent demo credentials for the shared demo
          school, newest first. Each send is also BCC&apos;d to
          support@lumi-reading.com.
        </CardDescription>
      </CardHeader>
      <CardContent>
        {emails.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            No demo-access emails have been sent yet.
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b text-left text-muted-foreground">
                  <th className="py-2 pr-4 font-medium">Sent</th>
                  <th className="py-2 pr-4 font-medium">Recipient</th>
                  <th className="py-2 pr-4 font-medium">Contact / School</th>
                  <th className="py-2 pr-4 font-medium">Status</th>
                  <th className="py-2 pr-4 font-medium">Requested by</th>
                  <th className="py-2 font-medium">Request</th>
                </tr>
              </thead>
              <tbody>
                {emails.map((e) => (
                  <tr key={e.id} className="border-b last:border-0">
                    <td className="py-2 pr-4 whitespace-nowrap">
                      {fmtSydney(e.sentAtISO || e.createdAtISO)}
                    </td>
                    <td className="py-2 pr-4">{e.to || "—"}</td>
                    <td className="py-2 pr-4">
                      <div>{e.contactPerson || "—"}</div>
                      <div className="text-xs text-muted-foreground">
                        {e.schoolName || "—"}
                      </div>
                    </td>
                    <td className="py-2 pr-4">
                      <StatusBadge status={e.status} />
                      {e.error && (
                        <div className="mt-1 text-xs text-destructive">
                          {e.error}
                        </div>
                      )}
                    </td>
                    <td className="py-2 pr-4 text-xs text-muted-foreground">
                      {e.requestedByEmail || "—"}
                    </td>
                    <td className="py-2">
                      {e.onboardingId ? (
                        <Link
                          href={`/onboarding/${e.onboardingId}`}
                          className="underline"
                        >
                          View
                        </Link>
                      ) : (
                        "—"
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
