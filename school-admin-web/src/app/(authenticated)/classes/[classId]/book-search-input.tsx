'use client';

import { useState, useMemo, useRef, useEffect } from 'react';
import { Input } from '@/components/lumi/input';
import { Button } from '@/components/lumi/button';
import { useBooks, useLookupIsbn } from '@/lib/hooks/use-books';
import { useToast } from '@/components/lumi/toast';

interface BookSearchInputProps {
  onAdd: (book: { title: string; bookId?: string; isbn?: string }) => void;
}

export function BookSearchInput({ onAdd }: BookSearchInputProps) {
  const { toast } = useToast();
  const { data: books } = useBooks();
  const lookupIsbn = useLookupIsbn();

  const [query, setQuery] = useState('');
  const [isbnInput, setIsbnInput] = useState('');
  const [showDropdown, setShowDropdown] = useState(false);
  const wrapperRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handleClick = (e: MouseEvent) => {
      if (wrapperRef.current && !wrapperRef.current.contains(e.target as Node)) {
        setShowDropdown(false);
      }
    };
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, []);

  const matches = useMemo(() => {
    if (!query.trim() || !books) return [];
    const q = query.toLowerCase().trim();
    return books
      .filter((b) => b.title.toLowerCase().includes(q) || b.author?.toLowerCase().includes(q))
      .slice(0, 8);
  }, [query, books]);

  const handleSelect = (book: { id: string; title: string; isbn?: string }) => {
    onAdd({ title: book.title, bookId: book.id, isbn: book.isbn });
    setQuery('');
    setShowDropdown(false);
  };

  const handleAddManual = () => {
    if (!query.trim()) return;
    onAdd({ title: query.trim() });
    setQuery('');
  };

  const handleIsbnLookup = async () => {
    if (!isbnInput.trim()) return;
    try {
      const result = await lookupIsbn.mutateAsync(isbnInput.trim());
      if (result.book) {
        onAdd({ title: result.book.title, bookId: result.book.id, isbn: result.book.isbn });
        setIsbnInput('');
        toast('Book found', 'success');
      } else {
        toast('No book found for this ISBN', 'error');
      }
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Lookup failed', 'error');
    }
  };

  return (
    <div className="space-y-2">
      <div ref={wrapperRef} className="relative">
        <div className="flex gap-2">
          <div className="flex-1">
            <Input
              value={query}
              onChange={(e) => { setQuery(e.target.value); setShowDropdown(true); }}
              placeholder="Search library by title..."
              onFocus={() => setShowDropdown(true)}
            />
          </div>
          <Button variant="outline" size="sm" onClick={handleAddManual} disabled={!query.trim()}>
            Add
          </Button>
        </div>

        {showDropdown && matches.length > 0 && (
          <div className="absolute z-10 top-full left-0 right-0 mt-1 bg-surface rounded-[var(--radius-md)] shadow-card-hover border border-divider max-h-48 overflow-y-auto">
            {matches.map((book) => (
              <button
                key={book.id}
                onClick={() => handleSelect(book)}
                className="w-full text-left px-3 py-2 hover:bg-background transition-colors text-sm"
              >
                <span className="font-semibold text-charcoal">{book.title}</span>
                {book.author && <span className="text-text-secondary ml-1">by {book.author}</span>}
              </button>
            ))}
          </div>
        )}
      </div>

      <div className="flex gap-2">
        <div className="flex-1">
          <Input
            value={isbnInput}
            onChange={(e) => setIsbnInput(e.target.value)}
            placeholder="Or enter ISBN..."
          />
        </div>
        <Button
          variant="outline"
          size="sm"
          onClick={handleIsbnLookup}
          loading={lookupIsbn.isPending}
          disabled={!isbnInput.trim()}
        >
          Lookup
        </Button>
      </div>
    </div>
  );
}
