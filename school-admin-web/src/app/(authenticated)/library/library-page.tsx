'use client';

import { useState, useMemo } from 'react';
import { PageHeader } from '@/components/lumi/page-header';
import { Button } from '@/components/lumi/button';
import { FilterChip } from '@/components/lumi/filter-chip';
import { SearchInput } from '@/components/lumi/search-input';
import { EmptyState } from '@/components/lumi/empty-state';
import { Icon } from '@/components/lumi/icon';
import { BookCard } from '@/components/lumi/book-card';
import { Badge } from '@/components/lumi/badge';
import { Skeleton } from '@/components/lumi/skeleton';
import { useToast } from '@/components/lumi/toast';
import { useBooks, useDeleteBook } from '@/lib/hooks/use-books';
import { BookFormModal } from './book-form-modal';
import { ConfirmDialog } from '@/components/lumi/confirm-dialog';
import type { ReadingLevelOption } from '@/lib/types';

type FilterType = 'all' | 'decodable' | 'library' | 'recent';

interface LibraryPageProps {
  levelOptions: ReadingLevelOption[];
}

export function LibraryPage({ levelOptions }: LibraryPageProps) {
  const { toast } = useToast();
  const { data: books, isLoading } = useBooks();
  const deleteBook = useDeleteBook();

  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState<FilterType>('all');
  const [showAddModal, setShowAddModal] = useState(false);
  const [editBookId, setEditBookId] = useState<string | null>(null);
  const [deleteConfirm, setDeleteConfirm] = useState<string | null>(null);

  const filtered = useMemo(() => {
    if (!books) return [];
    let result = [...books];

    // Filter by type
    if (filter === 'decodable') {
      result = result.filter((b) => b.metadata?.source === 'llll_local_db');
    } else if (filter === 'library') {
      result = result.filter((b) => b.metadata?.source !== 'llll_local_db');
    } else if (filter === 'recent') {
      const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
      result = result.filter((b) => b.createdAt > weekAgo);
    }

    // Search by title/author/ISBN
    if (search.trim()) {
      const q = search.toLowerCase().trim();
      result = result.filter(
        (b) =>
          b.title.toLowerCase().includes(q) ||
          b.author?.toLowerCase().includes(q) ||
          b.isbn?.includes(q)
      );
    }

    return result.sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }, [books, filter, search]);

  const filterCounts = useMemo(() => {
    if (!books) return { all: 0, decodable: 0, library: 0, recent: 0 };
    const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
    return {
      all: books.length,
      decodable: books.filter((b) => b.metadata?.source === 'llll_local_db').length,
      library: books.filter((b) => b.metadata?.source !== 'llll_local_db').length,
      recent: books.filter((b) => b.createdAt > weekAgo).length,
    };
  }, [books]);

  const handleDelete = async () => {
    if (!deleteConfirm) return;
    try {
      await deleteBook.mutateAsync(deleteConfirm);
      toast('Book deleted', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to delete', 'error');
    }
    setDeleteConfirm(null);
  };

  const editBook = editBookId ? books?.find((b) => b.id === editBookId) : null;

  return (
    <div>
      <PageHeader
        title="Library"
        description="School book library"
        action={
          <div className="flex gap-2">
            <Button variant="primary" onClick={() => setShowAddModal(true)}>
              Add Book
            </Button>
          </div>
        }
      />

      <div className="flex flex-wrap items-center gap-3 mb-4">
        {([
          { value: 'all', label: 'All', count: filterCounts.all },
          { value: 'decodable', label: 'Decodable', count: filterCounts.decodable },
          { value: 'library', label: 'Library', count: filterCounts.library },
          { value: 'recent', label: 'Recently Added', count: filterCounts.recent },
        ] as const).map((opt) => (
          <FilterChip
            key={opt.value}
            label={opt.label}
            count={opt.count}
            selected={filter === opt.value}
            onClick={() => setFilter(opt.value)}
          />
        ))}
      </div>

      <div className="mb-6">
        <SearchInput value={search} onChange={setSearch} placeholder="Search by title, author, or ISBN..." />
      </div>

      {isLoading ? (
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-4">
          {Array.from({ length: 8 }).map((_, i) => (
            <div key={i} className="bg-surface rounded-[var(--radius-lg)] shadow-card overflow-hidden">
              <Skeleton className="aspect-[3/4] w-full" />
              <div className="p-3 space-y-2">
                <Skeleton className="h-4 w-3/4" />
                <Skeleton className="h-3 w-1/2" />
              </div>
            </div>
          ))}
        </div>
      ) : filtered.length === 0 ? (
        <EmptyState
          icon={<Icon name="library_books" size={40} />}
          title={search ? 'No books found' : 'No books in library'}
          description={search ? 'Try a different search term.' : 'Add books manually or use ISBN lookup.'}
          action={!search ? <Button onClick={() => setShowAddModal(true)}>Add First Book</Button> : undefined}
        />
      ) : (
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-4">
          {filtered.map((book) => (
            <div key={book.id} className="group relative">
              <BookCard
                book={book}
                onClick={() => setEditBookId(book.id)}
                badge={
                  book.metadata?.source === 'llll_local_db' ? (
                    <Badge variant="info">
                      <span className="text-[10px]">Decodable</span>
                    </Badge>
                  ) : book.timesAssignedSchoolWide > 0 ? (
                    <Badge variant="success">
                      <span className="text-[10px]">{book.timesAssignedSchoolWide}x assigned</span>
                    </Badge>
                  ) : undefined
                }
              />
              <button
                onClick={(e) => { e.stopPropagation(); setDeleteConfirm(book.id); }}
                className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity p-1.5 rounded-full bg-surface/90 shadow-sm hover:bg-error/10 text-text-secondary hover:text-error"
              >
                <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                  <path d="M11 3L3 11M3 3l8 8" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
                </svg>
              </button>
            </div>
          ))}
        </div>
      )}

      <BookFormModal
        open={showAddModal || !!editBook}
        onClose={() => { setShowAddModal(false); setEditBookId(null); }}
        book={editBook ?? undefined}
        levelOptions={levelOptions}
      />

      <ConfirmDialog
        open={!!deleteConfirm}
        onClose={() => setDeleteConfirm(null)}
        onConfirm={handleDelete}
        title="Delete Book"
        description="This will permanently remove this book from your library. This cannot be undone."
        confirmLabel="Delete"
        variant="danger"
        loading={deleteBook.isPending}
      />
    </div>
  );
}
