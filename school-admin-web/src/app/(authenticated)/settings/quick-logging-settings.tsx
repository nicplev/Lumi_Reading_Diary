'use client';

import { useEffect, useState } from 'react';
import { Card } from '@/components/lumi/card';
import { Button } from '@/components/lumi/button';
import type { QuickLoggingSettings } from '@/lib/types';

interface QuickLoggingSettingsSectionProps {
  settings: QuickLoggingSettings | undefined;
  isAdmin: boolean;
  onSave: (settings: QuickLoggingSettings) => Promise<void>;
  saving: boolean;
}

/**
 * School-level control for the parent app's one-tap logging shortcut. Absent
 * setting = enabled so existing schools keep their current behaviour until an
 * admin explicitly turns it off.
 */
export function QuickLoggingSettingsSection({
  settings,
  isAdmin,
  onSave,
  saving,
}: QuickLoggingSettingsSectionProps) {
  const [enabled, setEnabled] = useState(true);

  useEffect(() => {
    setEnabled(settings?.enabled ?? true);
  }, [settings]);

  const dirty = (settings?.enabled ?? true) !== enabled;

  return (
    <Card>
      <h2 className="text-lg font-bold text-ink mb-1">Parent Quick Logging</h2>
      <p className="text-sm text-muted mb-4">
        Controls the parent app shortcut that records the target minutes and
        inferred books in one tap. When disabled, parents use the full Log
        reading flow so books, comments, feelings, and optional recordings are
        captured more deliberately.
      </p>

      <div className="mb-4 flex items-center gap-3">
        <button
          type="button"
          role="switch"
          aria-checked={enabled}
          aria-label="Allow parent quick logging"
          onClick={() => setEnabled((value) => !value)}
          disabled={!isAdmin}
          className={`relative inline-flex h-7 w-12 shrink-0 items-center rounded-full transition focus:outline-none focus:ring-2 focus:ring-rose-400 focus:ring-offset-2 ${
            enabled ? 'bg-rose-400' : 'bg-gray-300'
          } ${!isAdmin ? 'cursor-not-allowed opacity-60' : 'cursor-pointer'}`}
        >
          <span
            aria-hidden="true"
            className={`inline-block h-5 w-5 rounded-full bg-white shadow transition ${
              enabled ? 'translate-x-6' : 'translate-x-1'
            }`}
          />
        </button>
        <div>
          <span className="text-sm font-semibold text-ink">
            Allow parent quick logging
          </span>
          <p className="text-xs text-muted">
            Existing logs remain unchanged. This only controls whether new
            one-tap parent logs can be created.
          </p>
        </div>
      </div>

      {!enabled && (
        <div className="mb-4 rounded-lg border border-amber-300 bg-amber-50 px-4 py-3 text-sm text-amber-800">
          Parents will still be able to log reading, but the fast shortcut will
          be hidden and database rules will reject new quick-log writes.
        </div>
      )}

      {isAdmin && (
        <div className="flex justify-end">
          <Button
            onClick={() => onSave({ enabled })}
            loading={saving}
            disabled={!dirty}
          >
            Save
          </Button>
        </div>
      )}
    </Card>
  );
}
