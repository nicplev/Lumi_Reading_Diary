'use client';

import { useEffect, useState } from 'react';
import { Modal } from '@/components/lumi/modal';
import { Button } from '@/components/lumi/button';
import { Icon } from '@/components/lumi/icon';
import { allowedStaffCharacterIds, staffCharacterImageSrc } from '@/lib/staff-characters';

/** Role-gated character picker for staff. Admins see `la_*`; teachers see the
 *  combined `mt_*`+`ft_*` grid. Saves the chosen id via the parent's onSave. */
export function StaffCharacterPicker({
  open,
  onClose,
  role,
  currentId,
  onSave,
  saving,
}: {
  open: boolean;
  onClose: () => void;
  role: 'teacher' | 'schoolAdmin';
  currentId?: string;
  onSave: (characterId: string) => void;
  saving: boolean;
}) {
  const [selected, setSelected] = useState<string | undefined>(currentId);
  useEffect(() => {
    if (open) setSelected(currentId);
  }, [open, currentId]);

  const ids = allowedStaffCharacterIds(role);

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Choose your character"
      size="lg"
      footer={
        <>
          <Button variant="outline" onClick={onClose} disabled={saving}>
            Cancel
          </Button>
          <Button
            onClick={() => selected && onSave(selected)}
            loading={saving}
            disabled={!selected || selected === currentId}
          >
            Save
          </Button>
        </>
      }
    >
      <div className="grid grid-cols-4 sm:grid-cols-5 gap-3">
        {ids.map((id) => {
          const src = staffCharacterImageSrc(id);
          const isSelected = selected === id;
          return (
            <button
              key={id}
              type="button"
              onClick={() => setSelected(id)}
              className={`relative rounded-[var(--radius-md)] p-2 border-2 transition-colors ${
                isSelected ? 'border-section bg-section/5' : 'border-rule/40 hover:bg-cream'
              }`}
            >
              {src && <img src={src} alt="" className="w-full aspect-square object-contain" />}
              {isSelected && (
                <span className="absolute top-1 right-1 w-5 h-5 rounded-full bg-section text-white flex items-center justify-center">
                  <Icon name="check" size={12} />
                </span>
              )}
            </button>
          );
        })}
      </div>
    </Modal>
  );
}
