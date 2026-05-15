import { PageHeader } from "@/components/layout/page-header";
import { listLinkCodes } from "@/lib/firestore/link-codes";
import { LinkCodesTable } from "./link-codes-table";

export default async function LinkCodesPage() {
  const codes = await listLinkCodes();

  return (
    <>
      <PageHeader
        title="Student Link Codes"
        description="All link codes across schools"
      />
      <LinkCodesTable codes={codes} />
    </>
  );
}
