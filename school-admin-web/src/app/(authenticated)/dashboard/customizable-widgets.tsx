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
import { Button } from '@/components/lumi/button';
import { Icon } from '@/components/lumi/icon';

export interface DashboardWidgetDef {
  id: string;
  title: string;
  node: React.ReactNode;
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
 * Drag-to-reorder + show/hide for the teacher dashboard widget cards. Layout is
 * persisted in localStorage (per browser, keyed by user) per the agreed scope —
 * no backend. Reordering is enabled only in "Customize" mode.
 */
export function CustomizableWidgets({
  widgets,
  storageKey,
}: {
  widgets: DashboardWidgetDef[];
  storageKey: string;
}) {
  const [order, setOrder] = useState<string[]>(() => widgets.map((w) => w.id));
  const [hidden, setHidden] = useState<string[]>([]);
  const [editing, setEditing] = useState(false);

  // Hydrate from localStorage after mount (first render matches the server →
  // no hydration mismatch).
  useEffect(() => {
    const stored = loadLayout(storageKey);
    if (stored) {
      setOrder(stored.order);
      setHidden(stored.hidden);
    }
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
    setHidden([]);
    try {
      localStorage.removeItem(storageKey);
    } catch {
      /* ignore */
    }
  };

  const visible = editing ? orderedWidgets : orderedWidgets.filter((w) => !hidden.includes(w.id));
  const ids = visible.map((w) => w.id);

  return (
    <div>
      <div className="flex items-center justify-end gap-2 mb-3">
        {editing && (
          <Button variant="ghost" size="sm" onClick={reset}>
            Reset
          </Button>
        )}
        <Button variant="outline" size="sm" onClick={() => setEditing((e) => !e)}>
          {editing ? 'Done' : 'Customize'}
        </Button>
      </div>

      <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
        <SortableContext items={ids} strategy={rectSortingStrategy}>
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 items-start">
            {visible.map((w) => (
              <SortableWidget
                key={w.id}
                id={w.id}
                title={w.title}
                editing={editing}
                hidden={hidden.includes(w.id)}
                onToggleHide={() => toggleHide(w.id)}
              >
                {w.node}
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
  editing,
  hidden,
  onToggleHide,
  children,
}: {
  id: string;
  title: string;
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
    opacity: isDragging ? 0.6 : 1,
  };

  return (
    <div ref={setNodeRef} style={style}>
      {editing && (
        <div className="flex items-center justify-between mb-1.5 px-1">
          <button
            type="button"
            className="inline-flex items-center gap-1 text-xs font-semibold text-text-secondary cursor-grab active:cursor-grabbing touch-none"
            {...attributes}
            {...listeners}
          >
            <Icon name="drag_indicator" size={16} />
            {title}
          </button>
          <button
            type="button"
            onClick={onToggleHide}
            className={`text-xs font-semibold ${hidden ? 'text-rose-pink' : 'text-text-secondary hover:text-charcoal'}`}
          >
            {hidden ? 'Hidden — show' : 'Hide'}
          </button>
        </div>
      )}
      <div className={editing && hidden ? 'opacity-40' : ''}>{children}</div>
    </div>
  );
}
