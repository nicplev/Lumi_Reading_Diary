'use client';

import { useMemo, useState } from 'react';
import { PageHeader } from '@/components/lumi/page-header';
import { Button } from '@/components/lumi/button';
import { Card } from '@/components/lumi/card';
import { Badge } from '@/components/lumi/badge';
import { useToast } from '@/components/lumi/toast';
import type { RenewalRosterEntry } from '@/lib/firestore/renewals';

interface Props {
  currentYear: number;
  targetYear: number;
  subActive: boolean;
  initialRoster: RenewalRosterEntry[];
  /** False outside the Oct–Feb window → shows a soft "it's early" warning. */
  windowOpen?: boolean;
  /** True when rendered inside the Settings tab → drop the standalone header. */
  embedded?: boolean;
}

export function RenewalsPage({
  currentYear,
  targetYear,
  subActive,
  initialRoster,
  windowOpen = true,
  embedded = false,
}: Props) {
  const { toast } = useToast();
  const [roster] = useState(initialRoster);
  const [saving, setSaving] = useState(false);
  const [done, setDone] = useState<{ renewed: number; graduates: number } | null>(null);

  // Pre-tick everyone except graduates and the already-renewed.
  const [selected, setSelected] = useState<Set<string>>(
    () =>
      new Set(
        initialRoster
          .filter((s) => !s.graduated && !s.alreadyRenewed)
          .map((s) => s.studentId)
      )
  );

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
      setDone(body);
      toast(`Renewed ${body.renewed} student(s) into ${targetYear}.`, 'success');
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Renewal failed', 'error');
    } finally {
      setSaving(false);
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
        {done && (
          <span className="text-sm text-text-secondary">
            Renewed {done.renewed} · {done.graduates} graduate(s) flagged
          </span>
        )}
      </div>
    </div>
  );
}
