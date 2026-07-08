'use client';

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { PageHeader } from '@/components/lumi/page-header';
import { Button } from '@/components/lumi/button';
import { Card } from '@/components/lumi/card';
import { Badge } from '@/components/lumi/badge';
import { Select } from '@/components/lumi/select';
import { SearchInput } from '@/components/lumi/search-input';
import { useToast } from '@/components/lumi/toast';
import type { RenewalRosterEntry, RenewalBatchSummary } from '@/lib/firestore/renewals';

interface Props {
  currentYear: number;
  targetYear: number;
  subActive: boolean;
  initialRoster: RenewalRosterEntry[];
  /** False outside the Oct–Feb window → shows a soft "it's early" warning. */
  windowOpen?: boolean;
  /** True when rendered inside the Settings tab → drop the standalone header. */
  embedded?: boolean;
  /** Recent rollover batches, for the undo list. */
  recentBatches?: RenewalBatchSummary[];
}

type StatusKey = 'renewed' | 'graduate' | 'active' | 'expired' | 'suspended' | 'none';

/** Single status bucket per student — drives the Status column + the filter. */
function statusKey(s: RenewalRosterEntry): StatusKey {
  if (s.alreadyRenewed) return 'renewed';
  if (s.graduated) return 'graduate';
  return s.accessStatus ?? 'none';
}

const STATUS_FILTERS: { value: string; label: string }[] = [
  { value: 'all', label: 'All statuses' },
  { value: 'active', label: 'Active' },
  { value: 'expired', label: 'Expired' },
  { value: 'suspended', label: 'Suspended' },
  { value: 'none', label: 'No access' },
  { value: 'renewed', label: 'Already rolled over' },
  { value: 'graduate', label: 'Graduate' },
];

const PREP_SYNONYMS = ['prep', 'foundation', 'kindergarten', 'kinder', 'k', 'f'];

/** Natural rank for a free-form year level so sort/filter order sensibly. */
function yearRank(yl: string | null): number {
  if (!yl) return 9999;
  const t = yl.trim().toLowerCase();
  if (PREP_SYNONYMS.includes(t)) return 0;
  const m = t.match(/(\d+)/);
  return m ? Number(m[1]) : 5000;
}

export function RenewalsPage({
  currentYear,
  targetYear,
  subActive,
  initialRoster,
  windowOpen = true,
  embedded = false,
  recentBatches = [],
}: Props) {
  const { toast } = useToast();
  const router = useRouter();
  const roster = initialRoster;
  const [saving, setSaving] = useState(false);
  const [undoing, setUndoing] = useState<string | null>(null);

  // Pre-tick everyone except graduates and the already-rolled-over.
  const defaultSelection = () =>
    new Set(roster.filter((s) => !s.graduated && !s.alreadyRenewed).map((s) => s.studentId));
  const [selected, setSelected] = useState<Set<string>>(defaultSelection);
  useEffect(() => {
    setSelected(defaultSelection());
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initialRoster]);

  // ─── Toolbar state ───────────────────────────────────────────────────
  const [search, setSearch] = useState('');
  const [yearFilter, setYearFilter] = useState('all');
  const [statusFilter, setStatusFilter] = useState('all');
  const [sortBy, setSortBy] = useState('name');

  const yearOptions = useMemo(() => {
    const set = new Set<string>();
    roster.forEach((s) => s.currentYearLevel && set.add(s.currentYearLevel));
    const sorted = Array.from(set).sort((a, b) => yearRank(a) - yearRank(b) || a.localeCompare(b));
    return [{ value: 'all', label: 'All year levels' }, ...sorted.map((y) => ({ value: y, label: y }))];
  }, [roster]);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    const list = roster.filter((s) => {
      if (yearFilter !== 'all' && s.currentYearLevel !== yearFilter) return false;
      if (statusFilter !== 'all' && statusKey(s) !== statusFilter) return false;
      if (q && !`${s.firstName} ${s.lastName}`.toLowerCase().includes(q)) return false;
      return true;
    });
    const name = (s: RenewalRosterEntry) => `${s.lastName} ${s.firstName}`.trim().toLowerCase();
    const statusOrder: Record<StatusKey, number> = {
      none: 0, expired: 1, suspended: 2, active: 3, renewed: 4, graduate: 5,
    };
    list.sort((a, b) => {
      if (sortBy === 'name-desc') return name(b).localeCompare(name(a));
      if (sortBy === 'year') return (yearRank(a.currentYearLevel) - yearRank(b.currentYearLevel)) || name(a).localeCompare(name(b));
      if (sortBy === 'status') return (statusOrder[statusKey(a)] - statusOrder[statusKey(b)]) || name(a).localeCompare(name(b));
      return name(a).localeCompare(name(b));
    });
    return list;
  }, [roster, search, yearFilter, statusFilter, sortBy]);

  const stats = useMemo(() => {
    const graduates = roster.filter((s) => s.graduated).length;
    const alreadyRenewed = roster.filter((s) => s.alreadyRenewed).length;
    return { total: roster.length, graduates, alreadyRenewed, selected: selected.size };
  }, [roster, selected]);

  const filtersActive = search.trim() !== '' || yearFilter !== 'all' || statusFilter !== 'all';

  function toggle(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  /** Add every eligible (not graduated / not already rolled over) row in the
   *  current filtered view to the selection. */
  function selectAllFiltered() {
    setSelected((prev) => {
      const next = new Set(prev);
      filtered.forEach((s) => {
        if (!s.graduated && !s.alreadyRenewed) next.add(s.studentId);
      });
      return next;
    });
  }

  function deselectAllFiltered() {
    setSelected((prev) => {
      const next = new Set(prev);
      filtered.forEach((s) => next.delete(s.studentId));
      return next;
    });
  }

  async function confirm() {
    if (selected.size === 0) {
      toast('Select at least one student to roll over.', 'warning');
      return;
    }
    setSaving(true);
    try {
      const res = await fetch('/api/renewals', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ academicYear: targetYear, studentIds: Array.from(selected) }),
      });
      const body = await res.json();
      if (!res.ok) throw new Error(body.error ?? 'Rollover failed');
      toast(`Rolled ${body.renewed} student(s) forward into ${targetYear}. Undo below if needed.`, 'success');
      router.refresh();
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Rollover failed', 'error');
    } finally {
      setSaving(false);
    }
  }

  async function undo(batchId: string) {
    setUndoing(batchId);
    try {
      const res = await fetch('/api/renewals/undo', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ batchId }),
      });
      const body = await res.json();
      if (!res.ok) throw new Error(body.error ?? 'Undo failed');
      toast(`Undid rollover of ${body.reverted} student(s).`, 'success');
      router.refresh();
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Undo failed', 'error');
    } finally {
      setUndoing(null);
    }
  }

  function statusBadge(s: RenewalRosterEntry) {
    switch (statusKey(s)) {
      case 'renewed':
        return <Badge variant="success">Rolled over · {targetYear}</Badge>;
      case 'graduate':
        return <Badge>Graduate</Badge>;
      case 'active':
        return <Badge variant="success">Active · {s.accessYear ?? '—'}</Badge>;
      case 'expired':
        return <Badge variant="warning">Expired{s.accessYear ? ` · ${s.accessYear}` : ''}</Badge>;
      case 'suspended':
        return <Badge variant="error">Suspended</Badge>;
      default:
        return <span className="text-muted">No access</span>;
    }
  }

  return (
    <div className="space-y-6">
      {!embedded && (
        <PageHeader
          eyebrow="Rollover"
          title="Rollover"
          description={`Carry students forward into the ${targetYear} school year`}
        />
      )}
      {embedded && (
        <p className="text-sm text-muted">
          Roll students forward into the {targetYear} school year.
        </p>
      )}

      {!windowOpen && (
        <Card className="border-warning/40 bg-warning/5 p-4 text-sm text-ink">
          It&apos;s early — rollover for {targetYear} usually opens around October{' '}
          {currentYear} (start of Term 4). You can still roll students over now for an
          early or one-off case if you need to.
        </Card>
      )}

      <Card className="p-4 text-sm text-ink">
        <span className="font-semibold">Rolling into a new year?</span> Start with the{' '}
        <Link href="/students/rollover" className="text-section font-semibold hover:underline">
          Annual Rollover Import
        </Link>{' '}
        — it moves every student to their new class from your school system&apos;s class
        lists and handles graduates and leavers. Then come back here to grant {targetYear} access.
      </Card>

      {!subActive && (
        <Card className="border-error/40 bg-error/5 p-4 text-sm">
          Your school&apos;s Lumi subscription for {targetYear} is not active yet.
          Rollover is disabled until Lumi marks it paid — please contact Lumi.
        </Card>
      )}

      <Card className="p-4">
        <div className="flex flex-wrap gap-x-8 gap-y-2 text-sm">
          <span>Active students: <strong>{stats.total}</strong></span>
          <span>Selected to roll over: <strong>{stats.selected}</strong></span>
          <span>Graduates (excluded): <strong>{stats.graduates}</strong></span>
          <span>Already rolled over: <strong>{stats.alreadyRenewed}</strong></span>
        </div>
        <p className="mt-2 text-xs text-muted">
          Everyone is pre-ticked except graduates and students already rolled over.
          Untick anyone not returning (non-payers / leavers). Year levels are bumped
          automatically; class assignment stays manual.
        </p>
      </Card>

      {/* Toolbar — search / filter / sort for large rosters */}
      <div className="flex flex-wrap items-center gap-3">
        <div className="flex-1 min-w-[200px]">
          <SearchInput value={search} onChange={setSearch} placeholder="Search students by name..." />
        </div>
        <Select
          options={yearOptions}
          value={yearFilter}
          onChange={setYearFilter}
          className="!w-auto min-w-[150px]"
        />
        <Select
          options={STATUS_FILTERS}
          value={statusFilter}
          onChange={setStatusFilter}
          className="!w-auto min-w-[160px]"
        />
        <Select
          options={[
            { value: 'name', label: 'Sort: Name (A–Z)' },
            { value: 'name-desc', label: 'Sort: Name (Z–A)' },
            { value: 'year', label: 'Sort: Year level' },
            { value: 'status', label: 'Sort: Status' },
          ]}
          value={sortBy}
          onChange={setSortBy}
          className="!w-auto min-w-[170px]"
        />
      </div>

      {/* Bulk selection helpers, scoped to the current filter */}
      <div className="flex items-center gap-4 -mt-2">
        <span className="text-xs text-muted">
          Showing {filtered.length} of {roster.length}
        </span>
        <button onClick={selectAllFiltered} className="text-xs font-semibold text-section hover:underline">
          Select all{filtersActive ? ' shown' : ''}
        </button>
        <button onClick={deselectAllFiltered} className="text-xs font-semibold text-muted hover:underline">
          Deselect all{filtersActive ? ' shown' : ''}
        </button>
      </div>

      <Card className="overflow-hidden p-0">
        <div className="max-h-[60vh] overflow-auto">
          <table className="w-full text-sm">
            <thead className="sticky top-0 bg-paper z-10">
              <tr className="border-b border-rule text-left text-muted">
                <th className="w-10 p-3"></th>
                <th className="p-3">Student</th>
                <th className="p-3">Year level → next</th>
                <th className="p-3">Status</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((s) => (
                <tr key={s.studentId} className="border-b border-rule/60 last:border-0">
                  <td className="p-3">
                    <input
                      type="checkbox"
                      checked={selected.has(s.studentId)}
                      disabled={s.alreadyRenewed}
                      onChange={() => toggle(s.studentId)}
                      className="w-4 h-4 rounded border-rule text-section focus:ring-section/30 cursor-pointer disabled:opacity-50"
                    />
                  </td>
                  <td className="p-3 font-medium text-ink">
                    {s.firstName} {s.lastName}
                  </td>
                  <td className="p-3 text-ink">
                    {s.currentYearLevel ?? <span className="text-muted">—</span>}
                    {s.currentYearLevel && s.nextYearLevel && s.nextYearLevel !== s.currentYearLevel
                      ? ` → ${s.nextYearLevel}`
                      : ''}
                    {s.yearLevelSetByImport && (
                      <span className="ml-1.5 text-xs text-muted" title="The rollover import already set this year level — renewing won't change it.">
                        (set by import)
                      </span>
                    )}
                  </td>
                  <td className="p-3">{statusBadge(s)}</td>
                </tr>
              ))}
              {filtered.length === 0 && (
                <tr>
                  <td colSpan={4} className="p-6 text-center text-muted">
                    {roster.length === 0 ? 'No active students to roll over.' : 'No students match these filters.'}
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </Card>

      <div className="flex items-center gap-4">
        <Button onClick={confirm} loading={saving} disabled={!subActive || selected.size === 0}>
          Confirm {selected.size} rollover{selected.size === 1 ? '' : 's'}
        </Button>
      </div>

      {recentBatches.length > 0 && (
        <Card className="p-4">
          <h3 className="text-sm font-bold text-ink mb-1">Recent rollovers</h3>
          <p className="text-xs text-muted mb-3">
            Made a mistake? Undo restores those students to exactly how they were
            before — access, year level, and graduate flag.
          </p>
          <ul className="divide-y divide-rule">
            {recentBatches.map((b) => (
              <li key={b.id} className="flex items-center justify-between gap-4 py-2 text-sm">
                <span className="text-muted">
                  <strong className="text-ink">{b.count}</strong> student
                  {b.count === 1 ? '' : 's'} → {b.academicYear}
                  {b.performedAtIso ? ` · ${new Date(b.performedAtIso).toLocaleDateString()}` : ''}
                  {b.performedByName ? ` · ${b.performedByName}` : ''}
                </span>
                {b.status === 'applied' ? (
                  <Button variant="outline" size="sm" onClick={() => undo(b.id)} loading={undoing === b.id}>
                    Undo
                  </Button>
                ) : (
                  <Badge>Undone</Badge>
                )}
              </li>
            ))}
          </ul>
        </Card>
      )}
    </div>
  );
}
