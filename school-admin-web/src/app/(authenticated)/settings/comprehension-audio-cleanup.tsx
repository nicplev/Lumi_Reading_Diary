'use client';

import { useState } from 'react';
import { Card } from '@/components/lumi/card';
import { Input } from '@/components/lumi/input';
import { Select } from '@/components/lumi/select';
import { Button } from '@/components/lumi/button';
import { ConfirmDialog } from '@/components/lumi/confirm-dialog';
import { useToast } from '@/components/lumi/toast';
import { useClasses } from '@/lib/hooks/use-classes';

interface BulkPreviewResponse {
  count: number;
}

interface BulkDeleteResponse {
  deletedCount: number;
  failedCount: number;
}

/**
 * Bulk cleanup tool for comprehension audio. Lets a school admin preview the
 * count of recordings matching a date range (+ optional class), then delete
 * them. Used for end-of-year purges and one-off cleanups that don't fit the
 * platform-wide retention window. Backed by the
 * /api/comprehension-audio/bulk-delete + preview-count routes.
 */
export function ComprehensionAudioCleanupSection({ isAdmin }: { isAdmin: boolean }) {
  const { toast } = useToast();
  const { data: classes } = useClasses();
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');
  const [classId, setClassId] = useState('');
  const [previewCount, setPreviewCount] = useState<number | null>(null);
  const [previewing, setPreviewing] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [confirmOpen, setConfirmOpen] = useState(false);

  const filtersValid = startDate !== '' && endDate !== '' && startDate <= endDate;

  const resetPreview = () => setPreviewCount(null);

  const handlePreview = async () => {
    if (!filtersValid) {
      toast('Pick a start date and an end date (start ≤ end)', 'error');
      return;
    }
    setPreviewing(true);
    try {
      const params = new URLSearchParams({ startDate, endDate });
      if (classId) params.set('classId', classId);
      const res = await fetch(`/api/comprehension-audio/preview-count?${params.toString()}`);
      const json = (await res.json()) as BulkPreviewResponse | { error?: string };
      if (!res.ok) {
        throw new Error((json as { error?: string }).error ?? 'Preview failed');
      }
      setPreviewCount((json as BulkPreviewResponse).count);
    } catch (err) {
      toast(err instanceof Error ? err.message : 'Preview failed', 'error');
    } finally {
      setPreviewing(false);
    }
  };

  const handleDelete = async () => {
    setDeleting(true);
    setConfirmOpen(false);
    try {
      const res = await fetch('/api/comprehension-audio/bulk-delete', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          startDate,
          endDate,
          classId: classId || undefined,
        }),
      });
      const json = (await res.json()) as BulkDeleteResponse | { error?: string };
      if (!res.ok) {
        throw new Error((json as { error?: string }).error ?? 'Delete failed');
      }
      const result = json as BulkDeleteResponse;
      toast(
        `Deleted ${result.deletedCount} recording${result.deletedCount === 1 ? '' : 's'}` +
          (result.failedCount > 0 ? ` (${result.failedCount} failed)` : ''),
        'success'
      );
      resetPreview();
    } catch (err) {
      toast(err instanceof Error ? err.message : 'Delete failed', 'error');
    } finally {
      setDeleting(false);
    }
  };

  const classOptions = [
    { value: '', label: 'All classes' },
    ...(classes ?? []).map((c) => ({ value: c.id, label: c.name })),
  ];

  return (
    <Card>
      <h2 className="text-lg font-bold text-ink mb-1">Comprehension Audio Cleanup</h2>
      <p className="text-sm text-muted mb-4">
        Permanently delete comprehension recordings from a date range, optionally
        scoped to a single class. The reading log itself is preserved — only the
        audio file is removed. Use this for end-of-term or end-of-year cleanups
        beyond the platform-wide retention window.
      </p>

      {!isAdmin && (
        <p className="text-sm text-muted italic">
          Only school admins can run bulk cleanups.
        </p>
      )}

      {isAdmin && (
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <Input
              label="Start date"
              type="date"
              value={startDate}
              onChange={(e) => {
                setStartDate(e.target.value);
                resetPreview();
              }}
            />
            <Input
              label="End date"
              type="date"
              value={endDate}
              onChange={(e) => {
                setEndDate(e.target.value);
                resetPreview();
              }}
            />
          </div>
          <Select
            label="Class"
            options={classOptions}
            value={classId}
            onChange={(v) => {
              setClassId(v);
              resetPreview();
            }}
          />

          {previewCount !== null && (
            <div className="rounded-lg border border-rule bg-paper-muted px-4 py-3 text-sm text-ink">
              {previewCount === 0
                ? 'No recordings match this filter.'
                : `${previewCount} recording${previewCount === 1 ? '' : 's'} will be deleted.`}
            </div>
          )}

          <div className="flex justify-end gap-2">
            <Button
              variant="secondary"
              onClick={handlePreview}
              loading={previewing}
              disabled={!filtersValid || deleting}
            >
              Preview count
            </Button>
            <Button
              variant="danger"
              onClick={() => setConfirmOpen(true)}
              loading={deleting}
              disabled={
                !filtersValid || previewing || previewCount === null || previewCount === 0
              }
            >
              {previewCount !== null
                ? `Delete ${previewCount} recording${previewCount === 1 ? '' : 's'}`
                : 'Delete recordings'}
            </Button>
          </div>
        </div>
      )}

      <ConfirmDialog
        open={confirmOpen}
        onClose={() => setConfirmOpen(false)}
        onConfirm={handleDelete}
        title="Delete recordings permanently?"
        description={
          previewCount !== null
            ? `This will permanently delete ${previewCount} comprehension recording${previewCount === 1 ? '' : 's'} from ${startDate} to ${endDate}${classId ? ' for the selected class' : ''}. The reading logs themselves are preserved. This action cannot be undone.`
            : 'This will permanently delete all matching recordings. The reading logs themselves are preserved. This action cannot be undone.'
        }
        confirmLabel="Delete recordings"
        variant="warning"
        loading={deleting}
      />
    </Card>
  );
}
