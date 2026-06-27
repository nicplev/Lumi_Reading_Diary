'use client';

interface GroupRow {
  groupId: string;
  name: string;
  color: string | null;
  totalStudents: number;
  activeReaders: number;
  totalMinutes: number;
  avgMinutes: number;
}

/** Side-by-side average minutes per reading group this week (differentiated view). */
export function GroupComparison({ groups }: { groups: GroupRow[] }) {
  if (groups.length === 0) {
    return (
      <p className="text-sm text-muted h-full flex items-center">
        No reading groups yet. Create groups in a class to compare them here.
      </p>
    );
  }

  const max = Math.max(...groups.map((g) => g.avgMinutes), 1);

  return (
    <ul className="space-y-3 max-h-80 overflow-y-auto -mr-1 pr-1">
      {groups.map((g) => (
        <li key={g.groupId}>
          <div className="flex items-center justify-between gap-2 mb-1">
            <span className="text-sm font-semibold text-ink truncate flex items-center gap-1.5">
              <span
                className="w-2.5 h-2.5 rounded-full flex-shrink-0"
                style={{ backgroundColor: g.color ?? '#56C8E6' }}
              />
              {g.name}
            </span>
            <span className="text-xs text-muted whitespace-nowrap">{g.avgMinutes} min avg</span>
          </div>
          <div className="h-2 w-full rounded-[var(--radius-pill)] bg-cream overflow-hidden">
            <div
              className="h-full rounded-[var(--radius-pill)]"
              style={{ width: `${(g.avgMinutes / max) * 100}%`, backgroundColor: g.color ?? '#56C8E6' }}
            />
          </div>
          <p className="text-xs text-muted mt-1">
            {g.activeReaders}/{g.totalStudents} read this week
          </p>
        </li>
      ))}
    </ul>
  );
}
