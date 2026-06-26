'use client';

import { useEffect, useMemo, useState } from 'react';
import {
  DndContext,
  closestCenter,
  PointerSensor,
  KeyboardSensor,
  useSensor,
  useSensors,
  type DragEndEvent,
} from '@dnd-kit/core';
import { SortableContext, rectSortingStrategy, useSortable, arrayMove } from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import { Card } from '@/components/lumi/card';
import { Button } from '@/components/lumi/button';
import { Icon } from '@/components/lumi/icon';

export interface DashboardWidgetDef {
  id: string;
  title: string;
  /** Desktop footprint: 'lg' spans two columns (e.g. charts), 'md' spans one. */
  size?: 'md' | 'lg';
  /** Optional header action shown on the right of the title (e.g. a "View all" link). */
  action?: React.ReactNode;
  /** Card body only — the Card chrome + title header are provided by the wrapper. */
  body: React.ReactNode;
}

interface StoredLayout {
  order: string[];
  hidden: string[];
}

function loadLayout(key: string): StoredLayout | null {
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed?.order) && Array.isArray(parsed?.hidden)) {
      return { order: parsed.order as string[], hidden: parsed.hidden as string[] };
    }
  } catch {
    /* ignore */
  }
  return null;
}

/**
 * Drag-to-reorder + show/hide for the teacher dashboard widget cards. Each widget
 * supplies a title + body; this component owns the Card chrome so every card is
 * consistent and equal-height within its row. Widgets declare a `size` so the
 * default layout is an intentional bento (the chart spans two columns) rather
 * than a ragged uniform grid. Layout is persisted in localStorage (per browser,
 * keyed by user) per the agreed scope — no backend. Reordering/hiding is enabled
 * only in "Customize" mode.
 */
export function CustomizableWidgets({
  widgets,
  storageKey,
  defaultHidden = [],
}: {
  widgets: DashboardWidgetDef[];
  storageKey: string;
  /** Widget ids hidden by default (until the teacher shows them via Customize),
   *  applied only when there's no saved layout yet — keeps the first-run
   *  dashboard focused while every widget stays one click away. */
  defaultHidden?: string[];
}) {
  const [order, setOrder] = useState<string[]>(() => widgets.map((w) => w.id));
  const [hidden, setHidden] = useState<string[]>([]);
  const [editing, setEditing] = useState(false);

  // Hydrate from localStorage after mount (first render matches the server →
  // no hydration mismatch). With no saved layout, seed the default-hidden set.
  useEffect(() => {
    const stored = loadLayout(storageKey);
    if (stored) {
      setOrder(stored.order);
      setHidden(stored.hidden);
    } else if (defaultHidden.length > 0) {
      setHidden(defaultHidden);
    }
    // defaultHidden is intentionally read once on mount (a new array each render
    // would otherwise re-seed and fight the teacher's toggles).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [storageKey]);

  const persist = (nextOrder: string[], nextHidden: string[]) => {
    try {
      localStorage.setItem(storageKey, JSON.stringify({ order: nextOrder, hidden: nextHidden }));
    } catch {
      /* ignore */
    }
  };

  // Reconcile the saved order with the live widget set: keep known order, append
  // any new widgets, drop any that no longer exist.
  const orderedWidgets = useMemo(() => {
    const byId = new Map(widgets.map((w) => [w.id, w]));
    const known = order.filter((id) => byId.has(id));
    const appended = widgets.map((w) => w.id).filter((id) => !known.includes(id));
    return [...known, ...appended].map((id) => byId.get(id)).filter((w): w is DashboardWidgetDef => !!w);
  }, [order, widgets]);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } }),
    useSensor(KeyboardSensor)
  );

  const handleDragEnd = (event: DragEndEvent) => {
    const { active, over } = event;
    if (!over || active.id === over.id) return;
    const ids = orderedWidgets.map((w) => w.id);
    const from = ids.indexOf(active.id as string);
    const to = ids.indexOf(over.id as string);
    if (from < 0 || to < 0) return;
    const next = arrayMove(ids, from, to);
    setOrder(next);
    persist(next, hidden);
  };

  const toggleHide = (id: string) => {
    const next = hidden.includes(id) ? hidden.filter((h) => h !== id) : [...hidden, id];
    setHidden(next);
    persist(orderedWidgets.map((w) => w.id), next);
  };

  const reset = () => {
    setOrder(widgets.map((w) => w.id));
    setHidden(defaultHidden);
    try {
      localStorage.removeItem(storageKey);
    } catch {
      /* ignore */
    }
  };

  const hiddenCount = orderedWidgets.filter((w) => hidden.includes(w.id)).length;
  // In edit mode show every widget (hidden ones dimmed) so they can be toggled
  // back on; otherwise show only the visible set.
  const shown = editing ? orderedWidgets : orderedWidgets.filter((w) => !hidden.includes(w.id));
  const ids = shown.map((w) => w.id);

  return (
    <div>
      <div className="flex items-center justify-between gap-3 mb-4">
        <p className="text-sm text-text-secondary">
          {editing ? (
            <span className="inline-flex items-center gap-1.5">
              <Icon name="drag_indicator" size={16} className="text-text-secondary" />
              Drag to reorder · tap the eye to show or hide
            </span>
          ) : hiddenCount > 0 ? (
            `${hiddenCount} widget${hiddenCount === 1 ? '' : 's'} hidden`
          ) : (
            ''
          )}
        </p>
        <div className="flex items-center gap-2 shrink-0">
          {editing && (
            <Button variant="ghost" size="sm" onClick={reset}>
              Reset
            </Button>
          )}
          <Button variant="outline" size="sm" onClick={() => setEditing((e) => !e)}>
            <Icon name={editing ? 'check' : 'tune'} size={16} className="mr-1.5" />
            {editing ? 'Done' : 'Customize'}
          </Button>
        </div>
      </div>

      <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
        <SortableContext items={ids} strategy={rectSortingStrategy}>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5 items-stretch">
            {shown.map((w) => (
              <SortableWidget
                key={w.id}
                id={w.id}
                title={w.title}
                size={w.size}
                action={w.action}
                editing={editing}
                hidden={hidden.includes(w.id)}
                onToggleHide={() => toggleHide(w.id)}
              >
                {w.body}
              </SortableWidget>
            ))}
          </div>
        </SortableContext>
      </DndContext>
    </div>
  );
}

function SortableWidget({
  id,
  title,
  size,
  action,
  editing,
  hidden,
  onToggleHide,
  children,
}: {
  id: string;
  title: string;
  size?: 'md' | 'lg';
  action?: React.ReactNode;
  editing: boolean;
  hidden: boolean;
  onToggleHide: () => void;
  children: React.ReactNode;
}) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id,
    disabled: !editing,
  });
  const style: React.CSSProperties = {
    transform: CSS.Transform.toString(transform),
    transition,
  };
  // 'lg' spans two columns from the md breakpoint up (full width at md, 2/3 at lg).
  const span = size === 'lg' ? 'md:col-span-2' : '';

  return (
    <div ref={setNodeRef} style={style} className={`${span} ${isDragging ? 'z-10' : ''}`}>
      <Card
        padding="md"
        className={`h-full flex flex-col ${editing ? 'ring-1 ring-inset ring-rose-pink/30' : ''} ${
          isDragging ? 'shadow-card-hover' : ''
        } ${editing && hidden ? 'opacity-50' : ''}`}
      >
        <div className="flex items-center justify-between gap-2 mb-3 min-h-[28px]">
          {editing ? (
            <button
              type="button"
              className="inline-flex items-center gap-1.5 text-base font-bold text-charcoal cursor-grab active:cursor-grabbing touch-none -ml-1"
              {...attributes}
              {...listeners}
            >
              <Icon name="drag_indicator" size={18} className="text-text-secondary" />
              {title}
            </button>
          ) : (
            <h2 className="text-base font-bold text-charcoal">{title}</h2>
          )}
          {editing ? (
            <button
              type="button"
              onClick={onToggleHide}
              title={hidden ? 'Show widget' : 'Hide widget'}
              aria-label={hidden ? 'Show widget' : 'Hide widget'}
              className="inline-flex items-center justify-center w-7 h-7 rounded-[var(--radius-sm)] text-text-secondary hover:bg-background hover:text-charcoal transition-colors"
            >
              <Icon name={hidden ? 'visibility_off' : 'visibility'} size={18} />
            </button>
          ) : (
            action ?? null
          )}
        </div>
        <div className={`flex-1 min-h-0 ${editing ? 'pointer-events-none select-none' : ''}`}>{children}</div>
      </Card>
    </div>
  );
}
