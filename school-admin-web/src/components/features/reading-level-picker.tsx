'use client';

import { useState } from 'react';
import { Modal } from '@/components/lumi/modal';
import { Button } from '@/components/lumi/button';
import { Input } from '@/components/lumi/input';
import type { ReadingLevelOption } from '@/lib/types';

interface ReadingLevelPickerProps {
  open: boolean;
  onClose: () => void;
  currentLevel?: string;
  levelOptions: ReadingLevelOption[];
  onSelect: (level: string, reason?: string) => void;
  loading?: boolean;
}

export function ReadingLevelPicker({
  open,
  onClose,
  currentLevel,
  levelOptions,
  onSelect,
  loading,
}: ReadingLevelPickerProps) {
  const [selected, setSelected] = useState<string | null>(null);
  const [reason, setReason] = useState('');

  const handleConfirm = () => {
    if (selected) {
      onSelect(selected, reason || undefined);
    }
  };

  const handleClose = () => {
    setSelected(null);
    setReason('');
    onClose();
  };

  return (
    <Modal
      open={open}
      onClose={handleClose}
      title="Change Reading Level"
      description={currentLevel ? `Current level: ${currentLevel}` : 'No level set'}
      size="md"
      footer={
        <>
          <Button variant="outline" onClick={handleClose} disabled={loading}>
            Cancel
          </Button>
          <Button onClick={handleConfirm} disabled={!selected || loading} loading={loading}>
            Confirm
          </Button>
        </>
      }
    >
      <div className="grid grid-cols-5 sm:grid-cols-8 gap-2 mb-4">
        {levelOptions.map((opt) => (
          <button
            key={opt.value}
            onClick={() => setSelected(opt.value)}
            className={`px-2 py-2 rounded-[var(--radius-md)] text-sm font-bold text-center transition-colors ${
              selected === opt.value
                ? 'ring-2 ring-rose-pink bg-rose-pink/10 text-rose-pink-dark'
                : opt.value === currentLevel
                ? 'bg-background text-charcoal border-2 border-charcoal/20'
                : 'bg-background text-text-secondary hover:bg-divider/50'
            }`}
            style={
              opt.colorHex
                ? {
                    backgroundColor: selected === opt.value ? `${opt.colorHex}20` : `${opt.colorHex}10`,
                    color: opt.colorHex,
                  }
                : undefined
            }
          >
            {opt.shortLabel}
          </button>
        ))}
      </div>
      <Input
        label="Reason (optional)"
        value={reason}
        onChange={(e) => setReason(e.target.value)}
        placeholder="e.g. Assessment result, teacher observation"
      />
    </Modal>
  );
}
