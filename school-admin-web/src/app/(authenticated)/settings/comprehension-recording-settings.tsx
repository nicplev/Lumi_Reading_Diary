'use client';

import { useEffect, useState } from 'react';
import { Card } from '@/components/lumi/card';
import { Button } from '@/components/lumi/button';
import type { ComprehensionRecordingSettings } from '@/lib/types';

interface ComprehensionRecordingSettingsSectionProps {
  settings: ComprehensionRecordingSettings | undefined;
  isAdmin: boolean;
  onSave: (settings: ComprehensionRecordingSettings) => Promise<void>;
  saving: boolean;
  /** Platform-wide kill switch set from the Lumi super-admin portal. */
  globallyDisabled: boolean;
}

/**
 * Admin control for the optional comprehension voice-recording step in
 * the parent's reading-log wizard. When disabled, the step is hidden
 * across the whole school. Teachers can edit the per-class prompt
 * directly inside the teacher app; this toggle just gates whether the
 * step appears at all.
 */
export function ComprehensionRecordingSettingsSection({
  settings,
  isAdmin,
  onSave,
  saving,
  globallyDisabled,
}: ComprehensionRecordingSettingsSectionProps) {
  const [enabled, setEnabled] = useState(false);

  useEffect(() => {
    setEnabled(settings?.enabled ?? false);
  }, [settings]);

  const handleSave = () => {
    onSave({ enabled });
  };

  const dirty = (settings?.enabled ?? false) !== enabled;

  return (
    <Card>
      <h2 className="text-lg font-bold text-ink mb-1">Comprehension Recording</h2>
      <p className="text-sm text-muted mb-4">
        Adds an optional voice-recording step at the end of the parent&apos;s reading-log
        wizard so the child can briefly recap what they read. Teachers can edit the
        per-class prompt inside the teacher app.
      </p>

      {globallyDisabled && (
        <div className="mb-4 rounded-lg border border-amber-300 bg-amber-50 px-4 py-3 text-sm text-amber-800">
          Comprehension recording is temporarily unavailable platform-wide. It has been
          disabled by Lumi and cannot be turned on right now. Your saved preference is
          unchanged and will apply again when the feature is restored.
        </div>
      )}

      <label className="flex items-center gap-3 mb-6 cursor-pointer select-none">
        <input
          type="checkbox"
          checked={globallyDisabled ? false : enabled}
          onChange={(e) => setEnabled(e.target.checked)}
          disabled={!isAdmin || globallyDisabled}
          className="w-5 h-5 rounded border-gray-300 text-rose-400 focus:ring-rose-400 cursor-pointer"
        />
        <div>
          <span className="text-sm font-semibold text-ink">Enable comprehension recording</span>
          <p className="text-xs text-muted">
            When disabled, the recording step is hidden from parents and the per-class
            question tile is hidden from teachers. Recording is always optional per
            session — parents can skip.
          </p>
        </div>
      </label>

      {isAdmin && !globallyDisabled && (
        <div className="flex justify-end">
          <Button onClick={handleSave} loading={saving} disabled={!dirty}>
            Save
          </Button>
        </div>
      )}
    </Card>
  );
}
