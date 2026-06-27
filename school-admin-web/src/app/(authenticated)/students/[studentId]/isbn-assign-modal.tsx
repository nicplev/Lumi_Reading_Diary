'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import { Modal } from '@/components/lumi/modal';
import { Button } from '@/components/lumi/button';
import { Input } from '@/components/lumi/input';
import { FilterChip } from '@/components/lumi/filter-chip';
import { useToast } from '@/components/lumi/toast';
import { useBooks } from '@/lib/hooks/use-books';
import { useAssignIsbns, type AssignIsbnsResult } from '@/lib/hooks/use-isbn-assignment';

// Monday of the week `offsetWeeks` from now, in the browser's local time — this
// matches the app's device-local week so the deterministic allocation id lines
// up between the portal and the iPad scanner.
function mondayOf(offsetWeeks: number): Date {
  const d = new Date();
  const day = d.getDay();
  const dartWeekday = day === 0 ? 7 : day; // Sun→7, matching Dart's weekday
  d.setDate(d.getDate() - (dartWeekday - 1) + offsetWeeks * 7);
  d.setHours(0, 0, 0, 0);
  return d;
}

function ymd(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

function rangeLabel(monday: Date): string {
  const sun = new Date(monday);
  sun.setDate(sun.getDate() + 6);
  const opts: Intl.DateTimeFormatOptions = { day: 'numeric', month: 'short' };
  return `${monday.toLocaleDateString(undefined, opts)} – ${sun.toLocaleDateString(undefined, opts)}`;
}

const WEEK_OPTIONS = [
  { key: -1, label: 'Last week' },
  { key: 0, label: 'This week' },
  { key: 1, label: 'Next week' },
];

interface IsbnAssignModalProps {
  open: boolean;
  onClose: () => void;
  studentId: string;
  studentName?: string;
}

interface PickedBook {
  title: string;
  isbn?: string;
}

export function IsbnAssignModal({ open, onClose, studentId, studentName }: IsbnAssignModalProps) {
  const { toast } = useToast();
  const assign = useAssignIsbns();
  const { data: books } = useBooks();

  const [weekOffset, setWeekOffset] = useState(0);
  const [query, setQuery] = useState('');
  const [showDropdown, setShowDropdown] = useState(false);
  const [picked, setPicked] = useState<PickedBook[]>([]);
  const [text, setText] = useState('');
  const [result, setResult] = useState<AssignIsbnsResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const searchRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (open) {
      setWeekOffset(0);
      setQuery('');
      setShowDropdown(false);
      setPicked([]);
      setText('');
      setResult(null);
      setError(null);
    }
  }, [open]);

  useEffect(() => {
    const handle = (e: MouseEvent) => {
      if (searchRef.current && !searchRef.current.contains(e.target as Node)) setShowDropdown(false);
    };
    document.addEventListener('mousedown', handle);
    return () => document.removeEventListener('mousedown', handle);
  }, []);

  const monday = useMemo(() => mondayOf(weekOffset), [weekOffset]);

  const matches = useMemo(() => {
    if (!query.trim() || !books) return [];
    const q = query.toLowerCase().trim();
    return books
      .filter((b) => b.title.toLowerCase().includes(q) || b.author?.toLowerCase().includes(q))
      .slice(0, 8);
  }, [query, books]);

  const addBook = (book: PickedBook) => {
    setPicked((prev) =>
      prev.some((p) => (book.isbn && p.isbn === book.isbn) || p.title === book.title)
        ? prev
        : [...prev, book]
    );
    setQuery('');
    setShowDropdown(false);
  };

  const handleAssign = async () => {
    setError(null);
    setResult(null);
    const fromLibrary = picked.map((p) => p.isbn?.trim()).filter((x): x is string => !!x);
    const fromText = text.split(/[\s,]+/).map((s) => s.trim()).filter(Boolean);
    const isbns = [...new Set([...fromLibrary, ...fromText])];
    if (isbns.length === 0) {
      return setError(
        picked.some((p) => !p.isbn)
          ? 'The selected book(s) have no ISBN on file — pick a book with an ISBN, or enter one below.'
          : 'Pick a book from the library or enter an ISBN.'
      );
    }

    try {
      const r = await assign.mutateAsync({ studentId, isbns, weekStart: ymd(monday) });
      setResult(r);
      setPicked([]);
      setText('');
      if (r.assigned.length > 0) {
        toast(`Assigned ${r.assigned.length} book${r.assigned.length === 1 ? '' : 's'}`, 'success');
      } else if (r.duplicates.length > 0 && r.invalid.length === 0) {
        toast('Already assigned this week', 'success');
      }
    } catch (e) {
      const m = e instanceof Error ? e.message : 'Failed to assign books';
      setError(m);
      toast(m, 'error');
    }
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Assign Books"
      description={
        studentName
          ? `Assign books to ${studentName} for a week — pick from the school library or enter an ISBN.`
          : 'Assign books for a week from the library or by ISBN.'
      }
      footer={
        <>
          <Button variant="outline" onClick={onClose} disabled={assign.isPending}>
            Close
          </Button>
          <Button onClick={handleAssign} loading={assign.isPending}>
            Assign
          </Button>
        </>
      }
    >
      <form className="space-y-4" onSubmit={(e) => e.preventDefault()}>
        <div>
          <label className="block text-sm font-semibold text-ink mb-1.5">Week</label>
          <div className="flex flex-wrap gap-2">
            {WEEK_OPTIONS.map((w) => (
              <FilterChip
                key={w.key}
                label={w.label}
                selected={weekOffset === w.key}
                onClick={() => setWeekOffset(w.key)}
              />
            ))}
          </div>
          <p className="text-xs text-muted mt-1.5">{rangeLabel(monday)}</p>
        </div>

        {/* Pick from the school library */}
        <div ref={searchRef} className="relative">
          <label className="block text-sm font-semibold text-ink mb-1.5">From the school library</label>
          <Input
            value={query}
            onChange={(e) => {
              setQuery(e.target.value);
              setShowDropdown(true);
            }}
            onFocus={() => setShowDropdown(true)}
            placeholder="Search by title or author..."
          />
          {showDropdown && matches.length > 0 && (
            <div className="absolute z-10 top-full left-0 right-0 mt-1 bg-paper rounded-[var(--radius-md)] shadow-card-hover border border-rule max-h-48 overflow-y-auto">
              {matches.map((book) => (
                <button
                  key={book.id}
                  type="button"
                  onClick={() => addBook({ title: book.title, isbn: book.isbn })}
                  className="w-full text-left px-3 py-2 hover:bg-cream transition-colors text-sm"
                >
                  <span className="font-semibold text-ink">{book.title}</span>
                  {book.author && <span className="text-muted ml-1">by {book.author}</span>}
                  {!book.isbn && <span className="text-error text-xs ml-1">· no ISBN</span>}
                </button>
              ))}
            </div>
          )}
          {picked.length > 0 && (
            <div className="flex flex-wrap gap-2 mt-2">
              {picked.map((p, i) => (
                <span
                  key={`${p.title}-${i}`}
                  className={`inline-flex items-center gap-1 pl-2.5 pr-1.5 py-1 rounded-[var(--radius-pill)] text-sm ${
                    p.isbn ? 'bg-cream text-ink' : 'bg-error/10 text-error'
                  }`}
                >
                  {p.title}
                  {!p.isbn && ' · no ISBN'}
                  <button
                    type="button"
                    onClick={() => setPicked((prev) => prev.filter((_, idx) => idx !== i))}
                    className="ml-0.5 hover:opacity-70"
                    aria-label={`Remove ${p.title}`}
                  >
                    ×
                  </button>
                </span>
              ))}
            </div>
          )}
        </div>

        <div>
          <label className="block text-sm font-semibold text-ink mb-1.5">Or enter ISBNs</label>
          <textarea
            value={text}
            onChange={(e) => setText(e.target.value)}
            rows={3}
            placeholder="Type or paste ISBNs — one per line, or separated by spaces/commas"
            className="w-full px-4 py-3 rounded-[var(--radius-md)] border border-rule bg-paper text-ink placeholder:text-muted/50 focus:outline-none focus:ring-2 focus:ring-section/30 focus:border-section transition-colors text-[15px] resize-y font-mono"
          />
          <p className="text-xs text-muted mt-1">ISBN-10 or ISBN-13. Titles are looked up automatically.</p>
        </div>

        {result && (
          <div className="space-y-1.5 text-sm rounded-[var(--radius-md)] bg-cream p-3">
            {result.assigned.length > 0 && (
              <div>
                <p className="font-semibold text-lumi-green-dark">Assigned {result.assigned.length}:</p>
                <ul className="list-disc ml-5 text-ink">
                  {result.assigned.map((a) => (
                    <li key={a.isbn}>{a.title}</li>
                  ))}
                </ul>
              </div>
            )}
            {result.duplicates.length > 0 && (
              <p className="text-muted">
                {result.duplicates.length} already assigned this week — skipped.
              </p>
            )}
            {result.invalid.length > 0 && (
              <p className="text-error">{result.invalid.length} invalid ISBN(s): {result.invalid.join(', ')}</p>
            )}
          </div>
        )}

        {error && <p className="text-sm text-error">{error}</p>}
      </form>
    </Modal>
  );
}
