'use client';

import { Button } from '@/components/lumi/button';

interface UnsavedChangesBarProps {
  changeCount: number;
  onSave: () => void;
  onDiscard: () => void;
  isSaving: boolean;
}

export function UnsavedChangesBar({ changeCount, onSave, onDiscard, isSaving }: UnsavedChangesBarProps) {
  if (changeCount === 0) return null;

  return (
    <div className="fixed bottom-[calc(4rem+env(safe-area-inset-bottom))] right-0 left-0 z-40 flex items-center gap-3 border-t border-white/10 bg-ink px-4 py-3 lg:bottom-0 lg:left-[240px] lg:px-6">
      <span className="min-w-0 flex-1 text-sm text-white/80">
        {changeCount} unsaved change{changeCount !== 1 ? 's' : ''}
      </span>
      <Button variant="ghost" size="sm" onClick={onDiscard} disabled={isSaving} className="text-white/70 hover:text-white hover:bg-white/10">
        Discard
      </Button>
      <Button variant="primary" size="sm" onClick={onSave} loading={isSaving}>
        Save Changes
      </Button>
    </div>
  );
}
