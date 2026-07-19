'use client';

import { useMemo, useState } from 'react';
import Link from 'next/link';
import { Card } from '@/components/lumi/card';
import { Badge } from '@/components/lumi/badge';
import { Button } from '@/components/lumi/button';
import { Avatar } from '@/components/lumi/avatar';
import { useToast } from '@/components/lumi/toast';
import { useAddBookToAllocation, useRemoveBookFromAllocation } from '@/lib/hooks/use-allocations';
import { BookSearchInput } from './book-search-input';
import { useAuth } from '@/lib/auth/auth-context';

interface AllocationStudent {
  id: string;
  firstName: string;
  lastName: string;
  characterId?: string;
}

interface AllocationDetailProps {
  allocation: {
    id: string;
    type: string;
    cadence: string;
    targetMinutes: number;
    startDate: string;
    endDate: string;
    isActive: boolean;
    levelStart?: string;
    levelEnd?: string;
    studentIds: string[];
    assignmentItems: { id: string; title: string; bookId?: string; isbn?: string; isDeleted: boolean }[];
    studentOverrides: Record<string, {
      studentId: string;
      removedItemIds: string[];
      addedItems: { id: string; title: string; isDeleted: boolean }[];
    }>;
    demoEphemeral?: boolean;
  };
  students?: AllocationStudent[];
  onClose: () => void;
}

const typeLabels: Record<string, string> = {
  byTitle: 'By Title',
  byLevel: 'By Level',
  freeChoice: 'Free Choice',
};

const cadenceLabels: Record<string, string> = {
  daily: 'Daily',
  weekly: 'Weekly',
  fortnightly: 'Fortnightly',
  custom: 'Custom',
};

export function AllocationDetail({ allocation, students, onClose }: AllocationDetailProps) {
  const { toast } = useToast();
  const { user } = useAuth();
  const isDemo = user?.demoAllocationMutations === true;
  const addBook = useAddBookToAllocation();
  const removeBook = useRemoveBookFromAllocation();
  const [showAddBook, setShowAddBook] = useState(false);

  const studentById = useMemo(
    () => new Map((students ?? []).map((s) => [s.id, s])),
    [students]
  );
  const nameOf = (id: string) => {
    const s = studentById.get(id);
    return s ? `${s.firstName} ${s.lastName}` : null;
  };

  const activeItems = allocation.assignmentItems.filter((i) => !i.isDeleted);
  const now = new Date().toISOString();
  const isExpired = allocation.endDate < now;

  const handleRemoveBook = async (itemId: string) => {
    try {
      await removeBook.mutateAsync({ allocationId: allocation.id, itemId });
      toast('Book removed', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to remove book', 'error');
    }
  };

  const overrideEntries = Object.values(allocation.studentOverrides || {});

  return (
    <Card>
      <div className="flex items-start justify-between mb-4">
        <div className="flex items-center gap-2 flex-wrap">
          <Badge variant="info">{typeLabels[allocation.type] ?? allocation.type}</Badge>
          <Badge variant="default">{cadenceLabels[allocation.cadence] ?? allocation.cadence}</Badge>
          <Badge variant="default">{allocation.targetMinutes}min target</Badge>
          {allocation.isActive && !isExpired ? (
            <Badge variant="success">Active</Badge>
          ) : isExpired ? (
            <Badge variant="warning">Expired</Badge>
          ) : (
            <Badge variant="default">Inactive</Badge>
          )}
        </div>
        <Button variant="ghost" size="sm" onClick={onClose}>
          Close
        </Button>
      </div>

      <div className="text-xs text-muted mb-4">
        {new Date(allocation.startDate).toLocaleDateString()} - {new Date(allocation.endDate).toLocaleDateString()}
      </div>

      <div className="mb-4">
        <h4 className="text-sm font-semibold text-ink mb-1.5">Assigned to</h4>
        {allocation.studentIds.length === 0 ? (
          <p className="text-sm text-muted">Whole class</p>
        ) : (
          <div className="flex flex-wrap gap-2">
            {allocation.studentIds.map((sid) => (
              <Link
                key={sid}
                href={`/students/${sid}`}
                className="inline-flex items-center gap-1.5 pl-1 pr-2.5 py-1 rounded-[var(--radius-pill)] bg-cream text-sm text-ink hover:bg-rule/40 transition-colors"
              >
                <Avatar name={nameOf(sid) ?? sid} characterId={studentById.get(sid)?.characterId} size="xs" />
                {nameOf(sid) ?? 'Unknown student'}
              </Link>
            ))}
          </div>
        )}
      </div>

      {allocation.levelStart && (
        <div className="text-sm text-ink mb-4">
          Level range: <span className="font-semibold">{allocation.levelStart}</span> - <span className="font-semibold">{allocation.levelEnd}</span>
        </div>
      )}

      {/* Books List */}
      <div className="mb-4">
        <div className="flex items-center justify-between mb-2">
          <h4 className="text-sm font-semibold text-ink">Books ({activeItems.length})</h4>
          {allocation.isActive && !isDemo && (
            <Button variant="ghost" size="sm" onClick={() => setShowAddBook(!showAddBook)}>
              {showAddBook ? 'Cancel' : '+ Add Book'}
            </Button>
          )}
        </div>

        {showAddBook && (
          <div className="mb-3">
            <BookSearchInput
              onAdd={async (book) => {
                try {
                  await addBook.mutateAsync({
                    allocationId: allocation.id,
                    title: book.title,
                    bookId: book.bookId,
                    isbn: book.isbn,
                  });
                  toast('Book added to allocation', 'success');
                  setShowAddBook(false);
                } catch (error) {
                  toast(error instanceof Error ? error.message : 'Failed to add book', 'error');
                }
              }}
            />
          </div>
        )}

        {activeItems.length === 0 ? (
          <p className="text-sm text-muted">No books assigned.</p>
        ) : (
          <div className="space-y-1">
            {activeItems.map((item) => (
              <div
                key={item.id}
                className="flex items-center justify-between p-2 rounded-[var(--radius-md)] bg-cream"
              >
                <div className="flex items-center gap-2 min-w-0">
                  <span className="text-sm text-ink truncate">{item.title}</span>
                  {item.isbn && <Badge variant="default"><span className="text-[10px]">{item.isbn}</span></Badge>}
                </div>
                {allocation.isActive && !isDemo && (
                  <button
                    onClick={() => handleRemoveBook(item.id)}
                    className="text-muted hover:text-error transition-colors flex-shrink-0 ml-2"
                    disabled={removeBook.isPending}
                  >
                    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                      <path d="M11 3L3 11M3 3l8 8" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
                    </svg>
                  </button>
                )}
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Student Overrides */}
      {overrideEntries.length > 0 && (
        <div>
          <h4 className="text-sm font-semibold text-ink mb-2">Student Overrides ({overrideEntries.length})</h4>
          <div className="space-y-2">
            {overrideEntries.map((override) => (
              <div key={override.studentId} className="p-2 rounded-[var(--radius-md)] bg-cream text-xs">
                <span className="font-semibold text-ink">
                  {nameOf(override.studentId) ?? `Student ${override.studentId.slice(0, 8)}…`}
                </span>
                {override.removedItemIds.length > 0 && (
                  <span className="text-muted ml-2">{override.removedItemIds.length} removed</span>
                )}
                {override.addedItems.filter((i) => !i.isDeleted).length > 0 && (
                  <span className="text-muted ml-2">{override.addedItems.filter((i) => !i.isDeleted).length} added</span>
                )}
              </div>
            ))}
          </div>
        </div>
      )}
    </Card>
  );
}
