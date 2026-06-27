'use client';

import { useEffect, useState } from 'react';
import { Card } from '@/components/lumi/card';
import { Button } from '@/components/lumi/button';
import { useToast } from '@/components/lumi/toast';
import { useComprehensionQuestion, useSetComprehensionQuestion } from '@/lib/hooks/use-comprehension';

const MAX = 200;

export function ComprehensionQuestionCard({ classId }: { classId: string }) {
  const { toast } = useToast();
  const { data, isLoading } = useComprehensionQuestion(classId);
  const save = useSetComprehensionQuestion(classId);

  const [value, setValue] = useState('');
  const [editing, setEditing] = useState(false);

  useEffect(() => {
    if (data && !editing) setValue(data.question ?? '');
  }, [data, editing]);

  const effective = data?.question ?? data?.default ?? '';

  const handleSave = async () => {
    try {
      await save.mutateAsync(value);
      setEditing(false);
      toast('Comprehension question saved', 'success');
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Failed to save', 'error');
    }
  };

  const handleUseDefault = async () => {
    try {
      await save.mutateAsync('');
      setValue('');
      setEditing(false);
      toast('Reverted to the default question', 'success');
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Failed to save', 'error');
    }
  };

  return (
    <Card className="mb-4">
      <div className="flex items-start justify-between gap-3">
        <div className="flex-1">
          <h2 className="text-sm font-bold text-ink">Comprehension question</h2>
          <p className="text-xs text-muted mt-0.5">
            Shown to families at the end of a reading log for this class.
          </p>
        </div>
        {!editing && !isLoading && (
          <Button
            variant="outline"
            size="sm"
            onClick={() => {
              setValue(data?.question ?? '');
              setEditing(true);
            }}
          >
            Edit
          </Button>
        )}
      </div>

      {isLoading ? (
        <p className="text-sm text-muted mt-3">Loading…</p>
      ) : editing ? (
        <div className="mt-3 space-y-2">
          <textarea
            value={value}
            maxLength={MAX}
            rows={2}
            onChange={(e) => setValue(e.target.value)}
            placeholder={data?.default}
            className="w-full px-3 py-2 rounded-[var(--radius-md)] border border-rule bg-paper text-ink text-sm focus:outline-none focus:ring-2 focus:ring-section/30 focus:border-section transition-colors resize-y"
          />
          <div className="flex items-center justify-between">
            <span className="text-xs text-muted">
              {value.length}/{MAX}
              {!value.trim() ? ' · will use the default' : ''}
            </span>
            <div className="flex gap-2">
              <Button variant="ghost" size="sm" onClick={handleUseDefault} disabled={save.isPending}>
                Use default
              </Button>
              <Button variant="outline" size="sm" onClick={() => setEditing(false)} disabled={save.isPending}>
                Cancel
              </Button>
              <Button size="sm" onClick={handleSave} loading={save.isPending}>
                Save
              </Button>
            </div>
          </div>
        </div>
      ) : (
        <p className="mt-3 text-sm text-ink">
          &ldquo;{effective}&rdquo;
          {!data?.question && <span className="text-xs text-muted ml-2">(default)</span>}
        </p>
      )}
    </Card>
  );
}
