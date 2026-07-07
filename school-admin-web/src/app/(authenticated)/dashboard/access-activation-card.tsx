'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Card } from '@/components/lumi/card';
import { Button } from '@/components/lumi/button';
import { Icon } from '@/components/lumi/icon';
import { useToast } from '@/components/lumi/toast';

interface AccessActivationCardProps {
  studentsWithoutAccess: number;
  currentAcademicYear: number;
  subActive: boolean;
}

/**
 * Day-1 blocker card: some active students have no live `access`, so their
 * parents' reading logs are denied by the fail-closed rules. When the school
 * subscription is active the admin activates them in one click (self-serve
 * replacement for the backfill ops script); otherwise they're told to contact
 * Lumi. Renders nothing when every student already has access.
 */
export function AccessActivationCard({
  studentsWithoutAccess,
  currentAcademicYear,
  subActive,
}: AccessActivationCardProps) {
  const router = useRouter();
  const { toast } = useToast();
  const [activating, setActivating] = useState(false);

  if (studentsWithoutAccess <= 0) return null;

  const plural = studentsWithoutAccess === 1 ? '' : 's';

  const handleActivate = async () => {
    setActivating(true);
    try {
      const res = await fetch('/api/access/activate', { method: 'POST' });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || 'Activation failed');
      toast(
        `Reading activated for ${data.granted} student${data.granted === 1 ? '' : 's'}.`,
        'success'
      );
      router.refresh();
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Activation failed', 'error');
    } finally {
      setActivating(false);
    }
  };

  return (
    <Card className="border-warning/40 bg-warning/5">
      <div className="flex items-start gap-3">
        <span className="inline-flex items-center justify-center w-10 h-10 rounded-[var(--radius-md)] bg-warning/15 text-warning flex-shrink-0">
          <Icon name="lock" size={22} />
        </span>
        <div className="flex-1 min-w-0">
          <h2 className="text-lg font-bold text-ink">
            {studentsWithoutAccess} student{plural} can&apos;t log reading yet
          </h2>
          <p className="text-sm text-muted mt-1">
            Their reading access for {currentAcademicYear} isn&apos;t active, so
            parents will see a &ldquo;contact your school&rdquo; message when they
            try to log a session.
            {subActive
              ? ' Activate it now to unblock them.'
              : ' Your school subscription for this year isn’t active yet — contact Lumi to switch it on.'}
          </p>
          {subActive && (
            <div className="mt-4">
              <Button onClick={handleActivate} loading={activating}>
                <Icon name="lock_open" size={18} />
                <span className="ml-2">
                  Activate reading for {studentsWithoutAccess} student{plural}
                </span>
              </Button>
            </div>
          )}
        </div>
      </div>
    </Card>
  );
}
