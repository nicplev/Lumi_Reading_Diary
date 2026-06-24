'use client';

import { useEffect, useMemo, useState } from 'react';
import { Modal } from '@/components/lumi/modal';
import { Button } from '@/components/lumi/button';
import { FilterChip } from '@/components/lumi/filter-chip';
import { useToast } from '@/components/lumi/toast';
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

export function IsbnAssignModal({ open, onClose, studentId, studentName }: IsbnAssignModalProps) {
  const { toast } = useToast();
  const assign = useAssignIsbns();

  const [weekOffset, setWeekOffset] = useState(0);
  const [text, setText] = useState('');
  const [result, setResult] = useState<AssignIsbnsResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (open) {
      setWeekOffset(0);
      setText('');
      setResult(null);
      setError(null);
    }
  }, [open]);

  const monday = useMemo(() => mondayOf(weekOffset), [weekOffset]);

  const handleAssign = async () => {
    setError(null);
    setResult(null);
    const isbns = text.split(/[\s,]+/).map((s) => s.trim()).filter(Boolean);
    if (isbns.length === 0) return setError('Enter at least one ISBN.');

    try {
      const r = await assign.mutateAsync({ studentId, isbns, weekStart: ymd(monday) });
      setResult(r);
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
      title="Assign by ISBN"
      description={
        studentName
          ? `Assign books to ${studentName} for a week by ISBN — the same as scanning on the iPad.`
          : 'Assign books for a week by ISBN.'
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
          <label className="block text-sm font-semibold text-charcoal mb-1.5">Week</label>
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
          <p className="text-xs text-text-secondary mt-1.5">{rangeLabel(monday)}</p>
        </div>

        <div>
          <label className="block text-sm font-semibold text-charcoal mb-1.5">ISBNs</label>
          <textarea
            value={text}
            onChange={(e) => setText(e.target.value)}
            rows={4}
            placeholder="Type or paste ISBNs — one per line, or separated by spaces/commas"
            className="w-full px-4 py-3 rounded-[var(--radius-md)] border border-divider bg-surface text-charcoal placeholder:text-text-secondary/50 focus:outline-none focus:ring-2 focus:ring-rose-pink/30 focus:border-rose-pink transition-colors text-[15px] resize-y font-mono"
          />
          <p className="text-xs text-text-secondary mt-1">ISBN-10 or ISBN-13. Titles are looked up automatically.</p>
        </div>

        {result && (
          <div className="space-y-1.5 text-sm rounded-[var(--radius-md)] bg-background p-3">
            {result.assigned.length > 0 && (
              <div>
                <p className="font-semibold text-mint-green-dark">Assigned {result.assigned.length}:</p>
                <ul className="list-disc ml-5 text-charcoal">
                  {result.assigned.map((a) => (
                    <li key={a.isbn}>{a.title}</li>
                  ))}
                </ul>
              </div>
            )}
            {result.duplicates.length > 0 && (
              <p className="text-text-secondary">
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
