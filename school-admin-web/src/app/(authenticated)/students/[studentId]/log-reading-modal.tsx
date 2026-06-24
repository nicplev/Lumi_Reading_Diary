'use client';

import { useEffect, useState } from 'react';
import { Modal } from '@/components/lumi/modal';
import { Button } from '@/components/lumi/button';
import { Input } from '@/components/lumi/input';
import { useToast } from '@/components/lumi/toast';
import { useCreateTeacherLog } from '@/lib/hooks/use-reading-logs';

function isoDaysAgo(days: number): string {
  const d = new Date();
  d.setDate(d.getDate() - days);
  const local = new Date(d.getTime() - d.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 10);
}

interface LogReadingModalProps {
  open: boolean;
  onClose: () => void;
  studentId: string;
  studentName?: string;
  onLogged: () => void;
}

export function LogReadingModal({ open, onClose, studentId, studentName, onLogged }: LogReadingModalProps) {
  const { toast } = useToast();
  const createLog = useCreateTeacherLog();

  const [date, setDate] = useState(isoDaysAgo(0));
  const [minutes, setMinutes] = useState('20');
  const [titles, setTitles] = useState('');
  const [notes, setNotes] = useState('');
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (open) {
      setDate(isoDaysAgo(0));
      setMinutes('20');
      setTitles('');
      setNotes('');
      setError(null);
    }
  }, [open]);

  const handleSubmit = async () => {
    setError(null);
    const mins = parseInt(minutes, 10);
    if (!Number.isFinite(mins) || mins < 1 || mins > 240) {
      return setError('Minutes must be between 1 and 240.');
    }
    const bookTitles = titles.split(',').map((t) => t.trim()).filter(Boolean);
    if (bookTitles.length === 0) return setError('Add at least one book title.');

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
        <Input
          label="Book title(s)"
          placeholder="Separate multiple titles with commas"
          value={titles}
          onChange={(e) => setTitles(e.target.value)}
        />
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
