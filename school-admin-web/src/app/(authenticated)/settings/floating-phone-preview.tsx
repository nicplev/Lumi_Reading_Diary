'use client';

import { useState, useRef, useEffect, useCallback } from 'react';
import { ParentAppPreview } from './parent-app-preview';
import type { CommentPreviewState } from './parent-comment-settings';

const PANEL_W = 338;
const PANEL_H = 712; // phone + header, approx
const FAB_W = 168;
const MARGIN = 12;

/**
 * Draggable, collapsible "live preview" of the parent app comment screen.
 * Floats on top of the settings page so it never competes with the page
 * layout — the admin can move it anywhere and minimise it to a small FAB.
 */
export function FloatingPhonePreview({ enabled, freeTextEnabled, presets }: CommentPreviewState) {
  const [expanded, setExpanded] = useState(false);
  const [pos, setPos] = useState<{ x: number; y: number } | null>(null);
  const drag = useRef<{ sx: number; sy: number; ox: number; oy: number; moved: boolean } | null>(null);

  const clamp = useCallback((x: number, y: number, w: number, h: number) => {
    const maxX = window.innerWidth - w - MARGIN;
    const maxY = window.innerHeight - h - MARGIN;
    return {
      x: Math.max(MARGIN, Math.min(x, maxX)),
      y: Math.max(MARGIN, Math.min(y, maxY)),
    };
  }, []);

  // Initial position: bottom-right as a collapsed FAB.
  useEffect(() => {
    setPos(clamp(window.innerWidth - FAB_W - MARGIN, window.innerHeight - 60 - MARGIN, FAB_W, 56));
  }, [clamp]);

  // Keep it on-screen when the window resizes.
  useEffect(() => {
    const onResize = () => {
      setPos((p) => {
        if (!p) return p;
        const w = expanded ? PANEL_W : FAB_W;
        const h = expanded ? PANEL_H : 56;
        return clamp(p.x, p.y, w, h);
      });
    };
    window.addEventListener('resize', onResize);
    return () => window.removeEventListener('resize', onResize);
  }, [expanded, clamp]);

  const onPointerDown = (e: React.PointerEvent) => {
    if (!pos) return;
    drag.current = { sx: e.clientX, sy: e.clientY, ox: pos.x, oy: pos.y, moved: false };
    (e.currentTarget as Element).setPointerCapture(e.pointerId);
  };

  const onPointerMove = (e: React.PointerEvent) => {
    const d = drag.current;
    if (!d) return;
    const dx = e.clientX - d.sx;
    const dy = e.clientY - d.sy;
    if (!d.moved && Math.hypot(dx, dy) > 4) d.moved = true;
    if (!d.moved) return;
    const w = expanded ? PANEL_W : FAB_W;
    const h = expanded ? PANEL_H : 56;
    setPos(clamp(d.ox + dx, d.oy + dy, w, h));
  };

  const onPointerUp = (e: React.PointerEvent, onTap?: () => void) => {
    const d = drag.current;
    drag.current = null;
    try { (e.currentTarget as Element).releasePointerCapture(e.pointerId); } catch {}
    if (d && !d.moved) onTap?.();
  };

  const open = () => {
    setExpanded(true);
    // Reposition so the full panel is on-screen.
    setPos((p) => (p ? clamp(p.x - (PANEL_W - FAB_W), p.y - (PANEL_H - 56), PANEL_W, PANEL_H) : p));
  };

  const minimise = () => {
    setExpanded(false);
    setPos((p) => (p ? clamp(p.x, p.y, FAB_W, 56) : p));
  };

  if (!pos) return null;

  // Collapsed FAB
  if (!expanded) {
    return (
      <div
        style={{ position: 'fixed', left: pos.x, top: pos.y, zIndex: 50, touchAction: 'none' }}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={(e) => onPointerUp(e, open)}
      >
        <button
          type="button"
          className="flex items-center gap-2 rounded-full bg-charcoal px-4 py-3 text-sm font-semibold text-white shadow-lg hover:opacity-90"
          style={{ cursor: 'grab' }}
        >
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
            <rect x="6" y="2" width="12" height="20" rx="3" stroke="currentColor" strokeWidth="1.8" />
            <path d="M10 5h4" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
          </svg>
          Live preview
        </button>
      </div>
    );
  }

  // Expanded floating phone
  return (
    <div
      style={{
        position: 'fixed',
        left: pos.x,
        top: pos.y,
        zIndex: 50,
        width: PANEL_W,
        background: '#fff',
        borderRadius: 20,
        boxShadow: '0 24px 60px -12px rgba(0,0,0,0.35), 0 8px 20px -10px rgba(0,0,0,0.25)',
        border: '1px solid #E5E7EB',
      }}
    >
      {/* Drag handle / header */}
      <div
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={(e) => onPointerUp(e)}
        className="flex items-center justify-between"
        style={{
          padding: '10px 12px 10px 14px',
          cursor: 'grab',
          borderBottom: '1px solid #F0F0F2',
          touchAction: 'none',
          userSelect: 'none',
        }}
      >
        <div className="flex items-center gap-2 text-charcoal">
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" className="text-text-secondary">
            <circle cx="9" cy="6" r="1.4" fill="currentColor" /><circle cx="15" cy="6" r="1.4" fill="currentColor" />
            <circle cx="9" cy="12" r="1.4" fill="currentColor" /><circle cx="15" cy="12" r="1.4" fill="currentColor" />
            <circle cx="9" cy="18" r="1.4" fill="currentColor" /><circle cx="15" cy="18" r="1.4" fill="currentColor" />
          </svg>
          <span className="text-sm font-semibold">Parent app preview</span>
        </div>
        <div className="flex items-center gap-1">
          <button
            type="button"
            onClick={minimise}
            onPointerDown={(e) => e.stopPropagation()}
            title="Minimise"
            className="flex h-7 w-7 items-center justify-center rounded-md text-text-secondary hover:bg-gray-100"
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none"><path d="M5 12h14" stroke="currentColor" strokeWidth="2" strokeLinecap="round" /></svg>
          </button>
        </div>
      </div>

      {/* Phone */}
      <div style={{ padding: 12 }}>
        <ParentAppPreview enabled={enabled} freeTextEnabled={freeTextEnabled} presets={presets} />
      </div>
    </div>
  );
}
