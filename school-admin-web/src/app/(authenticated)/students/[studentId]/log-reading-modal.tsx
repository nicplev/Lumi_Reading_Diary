'use client';

import { useEffect, useMemo, useState } from 'react';
import { Modal } from '@/components/lumi/modal';
import { Button } from '@/components/lumi/button';
import { Input } from '@/components/lumi/input';
import { FilterChip } from '@/components/lumi/filter-chip';
import { useToast } from '@/components/lumi/toast';
import { useCreateTeacherLog } from '@/lib/hooks/use-reading-logs';
import { useStudentAllocations } from '@/lib/hooks/use-allocations';

function isoDaysAgo(days: number): string {
  const d = new Date();
  d.setDate(d.getDate() - days);
  const local = new Date(d.getTime() - d.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 10);
}

/** Case-insensitive de-dupe, preserving the first-seen casing. */
function dedupe(titles: string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const t of titles) {
    const key = t.toLowerCase();
    if (t && !seen.has(key)) {
      seen.add(key);
      out.push(t);
    }
  }
  return out;
}

interface LogReadingModalProps {
  open: boolean;
  onClose: () => void;
  studentId: string;
  classId: string;
  studentName?: string;
  onLogged: () => void;
}

export function LogReadingModal({
  open,
  onClose,
  studentId,
  classId,
  studentName,
  onLogged,
}: LogReadingModalProps) {
  const { toast } = useToast();
  const createLog = useCreateTeacherLog();
  const { data: allocations } = useStudentAllocations(studentId, classId);

  const [date, setDate] = useState(isoDaysAgo(0));
  const [minutes, setMinutes] = useState('20');
  const [selectedTitles, setSelectedTitles] = useState<string[]>([]);
  const [customTitles, setCustomTitles] = useState('');
  const [notes, setNotes] = useState('');
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (open) {
      setDate(isoDaysAgo(0));
      setMinutes('20');
      setSelectedTitles([]);
      setCustomTitles('');
      setNotes('');
      setError(null);
    }
  }, [open]);

  // The student's currently-assigned books, computed exactly like the Assigned
  // Books card (base items minus per-student removals, plus per-student adds).
  const assignedTitles = useMemo(() => {
    const titles: string[] = [];
    for (const a of allocations ?? []) {
      const override = a.studentOverrides?.[studentId];
      const baseItems = (a.assignmentItems ?? []).filter((i) => !i.isDeleted);
      const afterRemoval = override
        ? baseItems.filter((i) => !override.removedItemIds.includes(i.id))
        : baseItems;
      const addedItems = override ? override.addedItems.filter((i) => !i.isDeleted) : [];
      for (const item of [...afterRemoval, ...addedItems]) {
        if (item.title?.trim()) titles.push(item.title.trim());
      }
    }
    return dedupe(titles);
  }, [allocations, studentId]);

  const toggleTitle = (t: string) =>
    setSelectedTitles((prev) => (prev.includes(t) ? prev.filter((x) => x !== t) : [...prev, t]));

  const handleSubmit = async () => {
    setError(null);
    const mins = parseInt(minutes, 10);
    if (!Number.isFinite(mins) || mins < 1 || mins > 240) {
      return setError('Minutes must be between 1 and 240.');
    }

    const custom = customTitles.split(',').map((s) => s.trim()).filter(Boolean);
    const bookTitles = dedupe([...selectedTitles, ...custom]);
    if (bookTitles.length === 0) return setError('Select or add at least one book.');

    try {
      await createLog.mutateAsync({
        studentId,
        // Anchor to local noon so the date doesn't shift across the UTC boundary.
        date: new Date(`${date}T12:00:00`).toISOString(),
        minutesRead: mins,
        bookTitles,
        notes: notes.trim() || undefined,
      });
      toast('Reading logged', 'success');
      onLogged();
    } catch (e) {
      const m = e instanceof Error ? e.message : 'Failed to log reading';
      setError(m);
      toast(m, 'error');
    }
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Log Reading"
      description={studentName ? `Record a reading session for ${studentName}.` : 'Record a reading session.'}
      footer={
        <>
          <Button variant="outline" onClick={onClose} disabled={createLog.isPending}>
            Cancel
          </Button>
          <Button onClick={handleSubmit} loading={createLog.isPending}>
            Log Reading
          </Button>
        </>
      }
    >
      <form className="space-y-4" onSubmit={(e) => e.preventDefault()}>
        <Input
          label="Date"
          type="date"
          value={date}
          min={isoDaysAgo(7)}
          max={isoDaysAgo(0)}
          onChange={(e) => setDate(e.target.value)}
        />
        <Input
          label="Minutes read"
          type="number"
          min={1}
          max={240}
          value={minutes}
          onChange={(e) => setMinutes(e.target.value)}
        />

        <div>
          <label className="block text-sm font-semibold text-charcoal mb-1.5">Books read</label>
          {assignedTitles.length > 0 ? (
            <>
              <p className="text-xs text-text-secondary mb-2">Tap the assigned book(s) read in this session.</p>
              <div className="flex flex-wrap gap-2 mb-2">
                {assignedTitles.map((t) => (
                  <FilterChip
                    key={t}
                    label={t}
                    selected={selectedTitles.includes(t)}
                    onClick={() => toggleTitle(t)}
                  />
                ))}
              </div>
              <Input
                placeholder="Add another title not listed (comma-separated)"
                value={customTitles}
                onChange={(e) => setCustomTitles(e.target.value)}
              />
            </>
          ) : (
            <Input
              placeholder="Type the title(s), separated by commas"
              value={customTitles}
              onChange={(e) => setCustomTitles(e.target.value)}
            />
          )}
        </div>

        <div>
          <label className="block text-sm font-semibold text-charcoal mb-1.5">Notes (optional)</label>
          <textarea
            value={notes}
            maxLength={280}
            rows={3}
            onChange={(e) => setNotes(e.target.value)}
            placeholder="Anything worth noting about this session…"
            className="w-full px-4 py-3 rounded-[var(--radius-md)] border border-divider bg-surface text-charcoal placeholder:text-text-secondary/50 focus:outline-none focus:ring-2 focus:ring-rose-pink/30 focus:border-rose-pink transition-colors text-[15px] resize-y"
          />
        </div>

        {error && <p className="text-sm text-error">{error}</p>}
      </form>
    </Modal>
  );
}
