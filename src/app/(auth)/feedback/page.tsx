import { PageHeader } from "@/components/layout/page-header";
import { listFeedback } from "@/lib/firestore/feedback";
import { FeedbackTable } from "./feedback-table";

export default async function FeedbackPage() {
  const feedback = await listFeedback();

  return (
    <>
      <PageHeader
        title="Feedback"
        description="View and manage user feedback from the app"
      />
      <FeedbackTable data={feedback} />
    </>
  );
}
