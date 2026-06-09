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
      <h2 className="text-lg font-bold text-charcoal mb-1">Comprehension Recording</h2>
      <p className="text-sm text-text-secondary mb-4">
        Adds an optional voice-recording step at the end of the parent&apos;s reading-log
        wizard so the child can briefly recap what they read. Teachers can edit the
        per-class prompt inside the teacher app.
      </p>

      <label className="flex items-center gap-3 mb-6 cursor-pointer select-none">
        <input
          type="checkbox"
          checked={enabled}
          onChange={(e) => setEnabled(e.target.checked)}
          disabled={!isAdmin}
          className="w-5 h-5 rounded border-gray-300 text-rose-400 focus:ring-rose-400 cursor-pointer"
        />
        <div>
          <span className="text-sm font-semibold text-charcoal">Enable comprehension recording</span>
          <p className="text-xs text-text-secondary">
            When disabled, the recording step is hidden from parents and the per-class
            question tile is hidden from teachers. Recording is always optional per
            session — parents can skip.
          </p>
        </div>
      </label>

      {isAdmin && (
        <div className="flex justify-end">
          <Button onClick={handleSave} loading={saving} disabled={!dirty}>
            Save
          </Button>
        </div>
      )}
    </Card>
  );
}
