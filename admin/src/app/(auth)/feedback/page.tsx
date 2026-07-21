import { PageHeader } from "@/components/layout/page-header";
import { listFeedback } from "@/lib/firestore/feedback";
import { FeedbackTable } from "./feedback-table";

const feedbackStatuses = new Set(["all", "new", "reviewed", "resolved"]);

export default async function FeedbackPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; item?: string }>;
}) {
  const params = await searchParams;
  const feedback = await listFeedback();
  const initialStatus = feedbackStatuses.has(params.status ?? "")
    ? params.status!
    : "all";
  const initialItemId = feedback.some((item) => item.id === params.item)
    ? params.item
    : undefined;

  return (
    <>
      <PageHeader
        title="Feedback"
        description="View and manage user feedback from the app"
      />
      <FeedbackTable
        data={feedback}
        initialStatus={initialStatus}
        initialItemId={initialItemId}
      />
    </>
  );
}
