'use client';

import { useEffect, useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { PageHeader } from '@/components/lumi/page-header';
import { Button } from '@/components/lumi/button';
import { Card } from '@/components/lumi/card';
import { Badge } from '@/components/lumi/badge';
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
  /** Recent renewal batches, for the undo list. */
  recentBatches?: RenewalBatchSummary[];
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
  // Derived from props so router.refresh() (after renew/undo) updates it.
  const roster = initialRoster;
  const [saving, setSaving] = useState(false);
  const [undoing, setUndoing] = useState<string | null>(null);

  // Pre-tick everyone except graduates and the already-renewed.
  const [selected, setSelected] = useState<Set<string>>(
    () =>
      new Set(
        initialRoster
          .filter((s) => !s.graduated && !s.alreadyRenewed)
          .map((s) => s.studentId)
      )
  );
  // Reset the selection to the default whenever the roster reloads (refresh).
  useEffect(() => {
    setSelected(
      new Set(
        initialRoster
          .filter((s) => !s.graduated && !s.alreadyRenewed)
          .map((s) => s.studentId)
      )
    );
  }, [initialRoster]);

  const stats = useMemo(() => {
    const graduates = roster.filter((s) => s.graduated).length;
    const alreadyRenewed = roster.filter((s) => s.alreadyRenewed).length;
    return { total: roster.length, graduates, alreadyRenewed, selected: selected.size };
  }, [roster, selected]);

  function toggle(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  async function confirm() {
    if (selected.size === 0) {
      toast('Select at least one student to renew.', 'warning');
      return;
    }
    setSaving(true);
    try {
      const res = await fetch('/api/renewals', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          academicYear: targetYear,
          studentIds: Array.from(selected),
        }),
      });
      const body = await res.json();
      if (!res.ok) throw new Error(body.error ?? 'Renewal failed');
      toast(
        `Renewed ${body.renewed} student(s) into ${targetYear}. Undo below if needed.`,
        'success'
      );
      router.refresh();
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Renewal failed', 'error');
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
      toast(`Undid renewal of ${body.reverted} student(s).`, 'success');
      router.refresh();
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Undo failed', 'error');
    } finally {
      setUndoing(null);
    }
  }

  return (
    <div className="space-y-6">
      {!embedded && (
        <PageHeader
          title="Renewals"
          description={`Carry students forward into the ${targetYear} school year`}
        />
      )}
      {embedded && (
        <p className="text-sm text-text-secondary">
          Carry students forward into the {targetYear} school year.
        </p>
      )}

      {!windowOpen && (
        <Card className="border-warning/40 bg-warning/5 p-4 text-sm text-charcoal">
          It&apos;s early — renewals for {targetYear} usually open around October{' '}
          {currentYear} (start of Term 4). You can still renew now for an early or
          one-off case if you need to.
        </Card>
      )}

      {!subActive && (
        <Card className="border-error/40 bg-error/5 p-4 text-sm">
          Your school&apos;s Lumi subscription for {targetYear} is not active yet.
          Renewals are disabled until Lumi marks it paid — please contact Lumi.
        </Card>
      )}

      <Card className="p-4">
        <div className="flex flex-wrap gap-x-8 gap-y-2 text-sm">
          <span>Active students: <strong>{stats.total}</strong></span>
          <span>Selected to renew: <strong>{stats.selected}</strong></span>
          <span>Graduates (excluded): <strong>{stats.graduates}</strong></span>
          <span>Already renewed: <strong>{stats.alreadyRenewed}</strong></span>
        </div>
        <p className="mt-2 text-xs text-text-secondary">
          Everyone is pre-ticked except graduates and students already renewed.
          Untick anyone not returning (non-payers / leavers). Year levels are
          bumped automatically; class assignment stays manual.
        </p>
      </Card>

      <Card className="overflow-hidden p-0">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b text-left text-text-secondary">
              <th className="w-10 p-3"></th>
              <th className="p-3">Student</th>
              <th className="p-3">Year level → next</th>
              <th className="p-3">Status</th>
            </tr>
          </thead>
          <tbody>
            {roster.map((s) => (
              <tr key={s.studentId} className="border-b last:border-0">
                <td className="p-3">
                  <input
                    type="checkbox"
                    checked={selected.has(s.studentId)}
                    disabled={s.alreadyRenewed}
                    onChange={() => toggle(s.studentId)}
                  />
                </td>
                <td className="p-3 font-medium">
                  {s.firstName} {s.lastName}
                </td>
                <td className="p-3">
                  {s.currentYearLevel ?? '—'}
                  {s.nextYearLevel && s.nextYearLevel !== s.currentYearLevel
                    ? ` → ${s.nextYearLevel}`
                    : ''}
                </td>
                <td className="p-3">
                  {s.alreadyRenewed ? (
                    <Badge>Renewed</Badge>
                  ) : s.graduated ? (
                    <Badge>Graduate</Badge>
                  ) : (
                    <span className="text-text-secondary">—</span>
                  )}
                </td>
              </tr>
            ))}
            {roster.length === 0 && (
              <tr>
                <td colSpan={4} className="p-6 text-center text-text-secondary">
                  No active students to renew.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </Card>

      <div className="flex items-center gap-4">
        <Button
          onClick={confirm}
          loading={saving}
          disabled={!subActive || selected.size === 0}
        >
          Confirm {selected.size} renewal{selected.size === 1 ? '' : 's'}
        </Button>
      </div>

      {recentBatches.length > 0 && (
        <Card className="p-4">
          <h3 className="text-sm font-bold text-charcoal mb-1">Recent renewals</h3>
          <p className="text-xs text-text-secondary mb-3">
            Made a mistake? Undo restores those students to exactly how they were
            before the renewal — access, year level, and graduate flag.
          </p>
          <ul className="divide-y divide-divider">
            {recentBatches.map((b) => (
              <li
                key={b.id}
                className="flex items-center justify-between gap-4 py-2 text-sm"
              >
                <span className="text-text-secondary">
                  <strong className="text-charcoal">{b.count}</strong> student
                  {b.count === 1 ? '' : 's'} → {b.academicYear}
                  {b.performedAtIso
                    ? ` · ${new Date(b.performedAtIso).toLocaleDateString()}`
                    : ''}
                  {b.performedByName ? ` · ${b.performedByName}` : ''}
                </span>
                {b.status === 'applied' ? (
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => undo(b.id)}
                    loading={undoing === b.id}
                  >
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
