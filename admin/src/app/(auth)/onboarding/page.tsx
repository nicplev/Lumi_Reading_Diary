import { PageHeader } from "@/components/layout/page-header";
import { listOnboardingRequests } from "@/lib/firestore/onboarding";
import { OnboardingPipeline } from "./onboarding-pipeline";

export default async function OnboardingPage({
  searchParams,
}: {
  searchParams: Promise<{ view?: string }>;
}) {
  const { view } = await searchParams;
  const requests = await listOnboardingRequests();

  return (
    <>
      <PageHeader
        title="Onboarding Pipeline"
        description="Track school onboarding progress"
      />
      <OnboardingPipeline
        requests={requests}
        initialView={view === "leads" ? "leads" : undefined}
      />
    </>
  );
}
