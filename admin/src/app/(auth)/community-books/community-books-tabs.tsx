"use client";

import {
  Tabs,
  TabsContent,
  TabsList,
  TabsTrigger,
} from "@/components/ui/tabs";
import { CommunityBooksTable } from "./community-books-table";
import { DeletionRequestsTable } from "./deletion-requests-table";
import type { CommunityBookListItem, DeletionRequestListItem } from "@/lib/firestore/community-books";

interface CommunityBooksTabsProps {
  books: CommunityBookListItem[];
  deletionRequests: DeletionRequestListItem[];
  defaultTab?: string;
}

export function CommunityBooksTabs({
  books,
  deletionRequests,
  defaultTab,
}: CommunityBooksTabsProps) {
  return (
    <Tabs defaultValue={defaultTab || "collection"} className="space-y-4">
      <TabsList>
        <TabsTrigger value="collection">
          Collection ({books.length})
        </TabsTrigger>
        <TabsTrigger value="deletion-requests">
          Deletion Requests ({deletionRequests.length})
        </TabsTrigger>
      </TabsList>
      <TabsContent value="collection">
        <CommunityBooksTable data={books} />
      </TabsContent>
      <TabsContent value="deletion-requests">
        <DeletionRequestsTable data={deletionRequests} />
      </TabsContent>
    </Tabs>
  );
}
