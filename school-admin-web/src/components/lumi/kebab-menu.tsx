'use client';

import { useState, useRef, useEffect } from 'react';
import { createPortal } from 'react-dom';
import { Icon } from './icon';

interface KebabMenuItem {
  label: string;
  onClick: () => void;
  variant?: 'default' | 'danger';
}

interface KebabMenuProps {
  items: KebabMenuItem[];
}

const MENU_WIDTH = 160;
const ITEM_HEIGHT = 36;
const MENU_VERTICAL_PADDING = 8;
const GAP = 4;

export function KebabMenu({ items }: KebabMenuProps) {
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
      const menuHeight = items.length * ITEM_HEIGHT + MENU_VERTICAL_PADDING;
      const spaceBelow = window.innerHeight - rect.bottom;
      const openUp = spaceBelow < menuHeight + GAP + 8;
      const top = openUp ? rect.top - GAP - menuHeight : rect.bottom + GAP;
      const rawLeft = rect.right - MENU_WIDTH;
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
  }, [open, items.length]);

  return (
    <div className="inline-flex" onClick={(e) => e.stopPropagation()}>
      <button
        ref={buttonRef}
        onClick={() => setOpen((v) => !v)}
        className="inline-flex items-center justify-center w-8 h-8 rounded-[var(--radius-sm)] text-text-secondary hover:bg-background hover:text-charcoal transition-colors focus:outline-none focus-visible:outline-none"
        aria-label="More actions"
        aria-haspopup="menu"
        aria-expanded={open}
      >
        <Icon name="more_vert" size={18} />
      </button>

      {mounted && open && pos && createPortal(
        <div
          ref={menuRef}
          role="menu"
          style={{ position: 'fixed', top: pos.top, left: pos.left, width: MENU_WIDTH }}
          className="z-50 bg-surface border border-divider rounded-[var(--radius-md)] shadow-card py-1"
        >
          {items.map((item, i) => (
            <button
              key={i}
              role="menuitem"
              onClick={() => {
                setOpen(false);
                item.onClick();
              }}
              className={`w-full text-left px-4 py-2 text-sm font-semibold transition-colors hover:bg-background focus:outline-none ${
                item.variant === 'danger' ? 'text-error' : 'text-charcoal'
              }`}
            >
              {item.label}
            </button>
          ))}
        </div>,
        document.body
      )}
    </div>
  );
}
