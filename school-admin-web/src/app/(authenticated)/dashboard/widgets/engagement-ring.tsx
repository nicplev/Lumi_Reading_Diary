'use client';

/**
 * Today's reading participation as a progress ring — derived purely from the
 * existing TeacherDashboardData (read today / total students), no extra fetch.
 */
export function EngagementRing({
  readToday,
  totalStudents,
}: {
  readToday: number;
  totalStudents: number;
}) {
  const pct = totalStudents > 0 ? Math.round((readToday / totalStudents) * 100) : 0;
  const r = 52;
  const circ = 2 * Math.PI * r;
  const dash = (Math.min(pct, 100) / 100) * circ;

  return (
    <div className="h-full flex flex-col items-center justify-center gap-3 py-2">
      <div className="relative w-36 h-36">
        <svg viewBox="0 0 120 120" className="w-full h-full -rotate-90">
          <circle cx="60" cy="60" r={r} fill="none" stroke="#EDEAE3" strokeWidth="12" />
          <circle
            cx="60"
            cy="60"
            r={r}
            fill="none"
            stroke="#56C8E6"
            strokeWidth="12"
            strokeLinecap="round"
            strokeDasharray={`${dash} ${circ}`}
          />
        </svg>
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <span className="font-display text-3xl font-extrabold text-ink leading-none">{pct}%</span>
          <span className="text-xs text-muted mt-1">read today</span>
        </div>
      </div>
      <p className="text-sm text-muted">
        <span className="font-bold text-ink">{readToday}</span> of {totalStudents} students
      </p>
    </div>
  );
}
