import { PageHeader } from "@/components/layout/page-header";
import { listDevAccessEmails } from "@/lib/firestore/dev-access";
import { DevAccessTable } from "./dev-access-table";

export const dynamic = "force-dynamic";

export default async function DevAccessPage() {
  const emails = await listDevAccessEmails();

  return (
    <>
      <PageHeader
        title="Dev Access"
        description="Users who can see DEV-only surfaces in the Lumi mobile app and school admin portal."
      />
      <DevAccessTable initialEmails={emails} />
    </>
  );
}
