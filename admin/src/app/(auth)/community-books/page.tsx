import { PageHeader } from "@/components/layout/page-header";
import {
  listCommunityBooks,
  listPendingDeletionRequests,
} from "@/lib/firestore/community-books";
import { CommunityBooksTabs } from "./community-books-tabs";

export default async function CommunityBooksPage({
  searchParams,
}: {
  searchParams: Promise<{ tab?: string }>;
}) {
  const { tab } = await searchParams;

  const [books, deletionRequests] = await Promise.all([
    listCommunityBooks(),
    listPendingDeletionRequests(),
  ]);

  return (
    <>
      <PageHeader
        title="Community Books"
        description="Browse the shared community library and manage deletion requests"
      />
      <CommunityBooksTabs
        books={books}
        deletionRequests={deletionRequests}
        defaultTab={tab}
      />
    </>
  );
}
