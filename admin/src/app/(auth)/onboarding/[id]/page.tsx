import { notFound } from "next/navigation";
import { PageHeader } from "@/components/layout/page-header";
import { getOnboarding } from "@/lib/firestore/onboarding";
import { OnboardingDetail } from "./onboarding-detail";

export default async function OnboardingDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const onboarding = await getOnboarding(id);

  if (!onboarding) notFound();

  return (
    <>
      <PageHeader
        title={onboarding.schoolName}
        description="Onboarding request details"
      />
      <OnboardingDetail onboarding={onboarding} />
    </>
  );
}
