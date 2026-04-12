'use client';

import { useState, useRef, useEffect } from 'react';
import { Icon } from './icon';

interface KebabMenuItem {
  label: string;
  onClick: () => void;
  variant?: 'default' | 'danger';
}

interface KebabMenuProps {
  items: KebabMenuItem[];
}

export function KebabMenu({ items }: KebabMenuProps) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    function handleClickOutside(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false);
      }
    }
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [open]);

  return (
    <div ref={ref} className="relative inline-flex" onClick={(e) => e.stopPropagation()}>
      <button
        onClick={() => setOpen((v) => !v)}
        className="inline-flex items-center justify-center w-8 h-8 rounded-[var(--radius-sm)] text-text-secondary hover:bg-background hover:text-charcoal transition-colors focus:outline-none focus-visible:outline-none"
        aria-label="More actions"
      >
        <Icon name="more_vert" size={18} />
      </button>

      {open && (
        <div className="absolute right-0 top-full mt-1 z-50 bg-surface border border-divider rounded-[var(--radius-md)] shadow-card min-w-[160px] py-1">
          {items.map((item, i) => (
            <button
              key={i}
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
        </div>
      )}
    </div>
  );
}
