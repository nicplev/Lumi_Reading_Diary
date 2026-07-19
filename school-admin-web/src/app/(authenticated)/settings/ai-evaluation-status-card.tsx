'use client';

import { useEffect, useState } from 'react';
import { Card } from '@/components/lumi/card';
import { Icon } from '@/components/lumi/icon';

// Read-only status card for the AI comprehension-evaluation add-on.
// Deliberately no toggle: the entitlement is switched by Lumi per
// commercial agreement (and only after the school's privacy notice and
// terms are in place).
export function AiEvaluationStatusCard() {
  const [enabled, setEnabled] = useState<boolean | null>(null);

  useEffect(() => {
    let cancelled = false;
    fetch('/api/comprehension-evals/status')
      .then((res) => (res.ok ? res.json() : { enabled: false }))
      .then((data) => {
        if (!cancelled) setEnabled(data.enabled === true);
      })
      .catch(() => {
        if (!cancelled) setEnabled(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <Card className="p-5">
      <div className="flex items-start gap-3">
        <Icon name="graphic_eq" size={20} />
        <div className="min-w-0 flex-1">
          <div className="flex items-center justify-between gap-3">
            <h3 className="font-semibold">AI Comprehension Evaluation</h3>
            <span
              className={
                enabled
                  ? 'rounded-full bg-section-tint px-2.5 py-0.5 text-xs font-semibold text-section-strong'
                  : 'rounded-full bg-cream px-2.5 py-0.5 text-xs font-semibold text-muted'
              }
            >
              {enabled === null ? '…' : enabled ? 'Enabled' : 'Not enabled'}
            </span>
          </div>
          <p className="mt-1 text-sm text-muted">
            Transcribes children&apos;s spoken comprehension answers and gives
            teachers an AI summary against the class question — decision
            support, never formal assessment. This add-on is switched on by
            Lumi per agreement; contact Lumi to enable it for your school.
          </p>
        </div>
      </div>
    </Card>
  );
}
