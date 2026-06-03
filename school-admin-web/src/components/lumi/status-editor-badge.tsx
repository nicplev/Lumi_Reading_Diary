'use client';

import { useState, useRef, useEffect } from 'react';
import { createPortal } from 'react-dom';
import { Icon } from './icon';
import { Badge } from './badge';
import type { EnrollmentStatus } from '@/lib/types';

interface StatusEditorBadgeProps {
  status?: EnrollmentStatus;
  onChange: (next: EnrollmentStatus) => void | Promise<void>;
  disabled?: boolean;
}

type Option = {
  value: EnrollmentStatus;
  label: string;
  badge: { label: string; variant: 'success' | 'error' };
  showDirect?: boolean;
};

const OPTIONS: Option[] = [
  { value: 'book_pack', label: 'Subscribed', badge: { label: 'Subscribed', variant: 'success' } },
  {
    value: 'direct_purchase',
    label: 'Subscribed (Direct)',
    badge: { label: 'Subscribed', variant: 'success' },
    showDirect: true,
  },
  { value: 'not_enrolled', label: 'Not Subscribed', badge: { label: 'Not Subscribed', variant: 'error' } },
];

const MENU_WIDTH = 220;
const ITEM_HEIGHT = 40;
const MENU_VERTICAL_PADDING = 8;
const GAP = 4;

export function StatusEditorBadge({ status, onChange, disabled }: StatusEditorBadgeProps) {
  const current = OPTIONS.find((o) => o.value === status) ?? OPTIONS[2]; // default Not Subscribed

  const [open, setOpen] = useState(false);
  const [pos, setPos] = useState<{ top: number; left: number } | null>(null);
  const [mounted, setMounted] = useState(false);
  const buttonRef = useRef<HTMLButtonElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setMounted(true);
  }, []);

  useEffect(() => {
    if (!open || !buttonRef.current) return;

    const place = () => {
      const btn = buttonRef.current;
      if (!btn) return;
      const rect = btn.getBoundingClientRect();
      const menuHeight = OPTIONS.length * ITEM_HEIGHT + MENU_VERTICAL_PADDING;
      const spaceBelow = window.innerHeight - rect.bottom;
      const openUp = spaceBelow < menuHeight + GAP + 8;
      const top = openUp ? rect.top - GAP - menuHeight : rect.bottom + GAP;
      const rawLeft = rect.left;
      const left = Math.max(8, Math.min(rawLeft, window.innerWidth - MENU_WIDTH - 8));
      setPos({ top, left });
    };

    place();

    const handleClickOutside = (e: MouseEvent) => {
      const target = e.target as Node;
      if (buttonRef.current?.contains(target) || menuRef.current?.contains(target)) return;
      setOpen(false);
    };
    const handleDismiss = () => setOpen(false);

    document.addEventListener('mousedown', handleClickOutside);
    window.addEventListener('scroll', handleDismiss, true);
    window.addEventListener('resize', handleDismiss);

    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
      window.removeEventListener('scroll', handleDismiss, true);
      window.removeEventListener('resize', handleDismiss);
    };
  }, [open]);

  const handlePick = (value: EnrollmentStatus) => {
    setOpen(false);
    if (value !== status) {
      void onChange(value);
    }
  };

  return (
    <div className="inline-flex" onClick={(e) => e.stopPropagation()}>
      <button
        ref={buttonRef}
        type="button"
        disabled={disabled}
        onClick={() => setOpen((v) => !v)}
        title="Click to change subscription status"
        aria-haspopup="menu"
        aria-expanded={open}
        className="inline-flex items-center gap-1.5 rounded-[var(--radius-pill)] cursor-pointer transition-opacity hover:opacity-80 focus:outline-none focus-visible:ring-2 focus-visible:ring-rose-pink/40 disabled:opacity-50 disabled:cursor-not-allowed"
      >
        <span className="inline-flex items-center gap-0.5">
          <Badge variant={current.badge.variant}>{current.badge.label}</Badge>
          <Icon name="expand_more" size={16} className="text-text-secondary -ml-0.5" />
        </span>
        {current.showDirect && <Badge variant="info">Direct</Badge>}
      </button>

      {mounted && open && pos && createPortal(
        <div
          ref={menuRef}
          role="menu"
          style={{ position: 'fixed', top: pos.top, left: pos.left, width: MENU_WIDTH }}
          className="z-50 bg-surface border border-divider rounded-[var(--radius-md)] shadow-card py-1"
        >
          {OPTIONS.map((opt) => {
            const isCurrent = opt.value === status;
            return (
              <button
                key={opt.value}
                role="menuitem"
                onClick={() => handlePick(opt.value)}
                className={`w-full flex items-center justify-between gap-2 px-3 py-2 text-sm font-semibold transition-colors hover:bg-background focus:outline-none ${
                  isCurrent ? 'text-charcoal' : 'text-text-secondary'
                }`}
              >
                <span className="flex items-center gap-2">
                  <Badge variant={opt.badge.variant}>{opt.badge.label}</Badge>
                  {opt.showDirect && <Badge variant="info">Direct</Badge>}
                </span>
                {isCurrent && <Icon name="check" size={16} className="text-mint-green-dark" />}
              </button>
            );
          })}
        </div>,
        document.body
      )}
    </div>
  );
}
