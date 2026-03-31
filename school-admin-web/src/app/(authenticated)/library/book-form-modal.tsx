'use client';

import { useState, useEffect } from 'react';
import { Modal } from '@/components/lumi/modal';
import { Input } from '@/components/lumi/input';
import { Select } from '@/components/lumi/select';
import { Button } from '@/components/lumi/button';
import { Badge } from '@/components/lumi/badge';
import { ReadingLevelPill } from '@/components/lumi/reading-level-pill';
import { useToast } from '@/components/lumi/toast';
import { useCreateBook, useUpdateBook, useLookupIsbn } from '@/lib/hooks/use-books';
import type { ReadingLevelOption } from '@/lib/types';

interface BookFormModalProps {
  open: boolean;
  onClose: () => void;
  book?: { id: string; title: string; author?: string; isbn?: string; readingLevel?: string; coverImageUrl?: string };
  levelOptions: ReadingLevelOption[];
}

export function BookFormModal({ open, onClose, book, levelOptions }: BookFormModalProps) {
  const { toast } = useToast();
  const createBook = useCreateBook();
  const updateBook = useUpdateBook();
  const lookupIsbn = useLookupIsbn();
  const isEdit = !!book;

  const [editing, setEditing] = useState(false);
  const [title, setTitle] = useState('');
  const [author, setAuthor] = useState('');
  const [isbn, setIsbn] = useState('');
  const [readingLevel, setReadingLevel] = useState('');
  const [coverImageUrl, setCoverImageUrl] = useState('');

  useEffect(() => {
    if (open) {
      setTitle(book?.title ?? '');
      setAuthor(book?.author ?? '');
      setIsbn(book?.isbn ?? '');
      setReadingLevel(book?.readingLevel ?? '');
      setCoverImageUrl(book?.coverImageUrl ?? '');
      setEditing(!isEdit); // View mode for existing books, edit mode for new
    }
  }, [open, book, isEdit]);

  const handleLookup = async () => {
    if (!isbn.trim()) return;
    try {
      const result = await lookupIsbn.mutateAsync(isbn.trim());
      if (result.book) {
        if (!title) setTitle(result.book.title);
        if (!author && result.book.author) setAuthor(result.book.author);
        if (!coverImageUrl && result.book.coverImageUrl) setCoverImageUrl(result.book.coverImageUrl);
        toast('Book found via ISBN lookup', 'success');
      } else {
        toast('No book found for this ISBN', 'error');
      }
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Lookup failed', 'error');
    }
  };

  const handleSubmit = async () => {
    if (!title.trim()) return;
    try {
      const data = {
        title: title.trim(),
        author: author.trim() || undefined,
        isbn: isbn.trim() || undefined,
        readingLevel: readingLevel || undefined,
        coverImageUrl: coverImageUrl.trim() || undefined,
      };

      if (isEdit) {
        await updateBook.mutateAsync({ bookId: book.id, ...data });
        toast('Book updated', 'success');
      } else {
        await createBook.mutateAsync(data);
        toast('Book added to library', 'success');
      }
      onClose();
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to save book', 'error');
    }
  };

  const isPending = createBook.isPending || updateBook.isPending;

  // View mode for existing books
  if (isEdit && !editing) {
    return (
      <Modal
        open={open}
        onClose={onClose}
        title={book.title}
        size="md"
        footer={
          <>
            <Button variant="outline" onClick={onClose}>Close</Button>
            <Button onClick={() => setEditing(true)}>Edit</Button>
          </>
        }
      >
        <div className="space-y-4">
          {coverImageUrl && (
            <div className="flex justify-center">
              <div className="w-28 h-36 rounded-[var(--radius-md)] bg-background overflow-hidden shadow-card">
                <img src={coverImageUrl} alt={book.title} className="w-full h-full object-cover" onError={(e) => { (e.target as HTMLImageElement).style.display = 'none'; }} />
              </div>
            </div>
          )}
          <div className="space-y-3">
            {author && (
              <div>
                <p className="text-xs font-semibold text-text-secondary">Author</p>
                <p className="text-sm text-charcoal">{author}</p>
              </div>
            )}
            {isbn && (
              <div>
                <p className="text-xs font-semibold text-text-secondary">ISBN</p>
                <p className="text-sm text-charcoal font-mono">{isbn}</p>
              </div>
            )}
            <div>
              <p className="text-xs font-semibold text-text-secondary">Reading Level</p>
              {readingLevel ? (
                <ReadingLevelPill level={readingLevel} size="sm" />
              ) : (
                <Badge variant="default">Not set</Badge>
              )}
            </div>
          </div>
        </div>
      </Modal>
    );
  }

  // Edit / Create mode
  return (
    <Modal
      open={open}
      onClose={onClose}
      title={isEdit ? 'Edit Book' : 'Add Book'}
      description={isEdit ? 'Update book details.' : 'Add a book manually or look up by ISBN.'}
      size="md"
      footer={
        <>
          <Button variant="outline" onClick={isEdit ? () => setEditing(false) : onClose} disabled={isPending}>
            {isEdit ? 'Cancel Edit' : 'Cancel'}
          </Button>
          <Button onClick={handleSubmit} loading={isPending} disabled={!title.trim()}>
            {isEdit ? 'Save Changes' : 'Add Book'}
          </Button>
        </>
      }
    >
      <div className="space-y-4">
        <div className="flex gap-2">
          <div className="flex-1">
            <Input
              label="ISBN"
              value={isbn}
              onChange={(e) => setIsbn(e.target.value)}
              placeholder="e.g. 978-0-13-468599-1"
            />
          </div>
          <div className="flex items-end">
            <Button
              variant="outline"
              onClick={handleLookup}
              loading={lookupIsbn.isPending}
              disabled={!isbn.trim()}
            >
              Lookup
            </Button>
          </div>
        </div>

        <Input
          label="Title"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="Book title"
          required
        />

        <Input
          label="Author"
          value={author}
          onChange={(e) => setAuthor(e.target.value)}
          placeholder="Author name"
        />

        <Select
          label="Reading Level"
          options={levelOptions.map((l) => ({ value: l.value, label: l.displayLabel }))}
          value={readingLevel}
          onChange={setReadingLevel}
          placeholder="Select level (optional)"
        />

        <Input
          label="Cover Image URL"
          value={coverImageUrl}
          onChange={(e) => setCoverImageUrl(e.target.value)}
          placeholder="https://..."
        />

        {coverImageUrl && (
          <div className="flex justify-center">
            <div className="w-24 h-32 rounded bg-background overflow-hidden">
              <img
                src={coverImageUrl}
                alt="Cover preview"
                className="w-full h-full object-cover"
                onError={(e) => { (e.target as HTMLImageElement).style.display = 'none'; }}
              />
            </div>
          </div>
        )}
      </div>
    </Modal>
  );
}
