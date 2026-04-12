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
    <div className="fixed bottom-0 right-0 left-0 lg:left-[240px] z-40 px-6 py-3 bg-charcoal/95 backdrop-blur-sm border-t border-white/10 flex items-center gap-3">
      <span className="text-sm text-white/80 flex-1">
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
