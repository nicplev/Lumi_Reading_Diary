import Link from "next/link";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { listInvoices } from "@/lib/firestore/invoices";
import { getBillingEntity } from "@/lib/firestore/billing-entity";
import { InvoiceRegister } from "./invoice-register";

export const dynamic = "force-dynamic";

export default async function InvoicingPage() {
  const [invoices, entity] = await Promise.all([
    listInvoices(),
    getBillingEntity(),
  ]);
  const entityReady = Boolean(entity.legalName && entity.abn);

  return (
    <>
      <PageHeader
        title="Invoicing"
        description="Create and track Lumi invoices"
        actions={
          <div className="flex gap-2">
            <Link href="/operations/invoicing/settings">
              <Button variant="outline">Billing details</Button>
            </Link>
            <Link href="/operations/invoicing/new">
              <Button>New invoice</Button>
            </Link>
          </div>
        }
      />
      {!entityReady && (
        <div className="mb-4 rounded-md border border-yellow-300 bg-yellow-50 px-4 py-3 text-sm text-yellow-900">
          The Lumi billing entity (legal name + ABN) is not set yet — invoices
          are not legally valid until you complete{" "}
          <Link href="/operations/invoicing/settings" className="underline font-medium">
            Billing details
          </Link>
          .
        </div>
      )}
      <InvoiceRegister invoices={invoices} />
    </>
  );
}
