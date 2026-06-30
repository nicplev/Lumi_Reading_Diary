'use client';

import { useEffect, useState } from 'react';
import { Card } from '@/components/lumi/card';
import { Button } from '@/components/lumi/button';
import type { MessagingSettings } from '@/lib/types';

interface MessagingSettingsSectionProps {
  settings: MessagingSettings | undefined;
  isAdmin: boolean;
  onSave: (settings: MessagingSettings) => Promise<void>;
  saving: boolean;
}

/**
 * Admin control for the parent↔teacher messaging threads attached to reading
 * logs. When disabled, the comment thread, composer, and unread badges are
 * hidden across the app for this school, so parents and teachers can no longer
 * message each other about a reading session. Absent setting = enabled, so
 * existing schools keep messaging until an admin opts out.
 */
export function MessagingSettingsSection({
  settings,
  isAdmin,
  onSave,
  saving,
}: MessagingSettingsSectionProps) {
  const [enabled, setEnabled] = useState(true);

  useEffect(() => {
    setEnabled(settings?.enabled ?? true);
  }, [settings]);

  const handleSave = () => {
    onSave({ enabled });
  };

  const dirty = (settings?.enabled ?? true) !== enabled;

  return (
    <Card>
      <h2 className="text-lg font-bold text-ink mb-1">Parent-Teacher Messaging</h2>
      <p className="text-sm text-muted mb-4">
        Lets parents and teachers exchange messages on a reading log — a private
        thread per session. When disabled, the message thread is hidden for both
        parents and teachers across this school.
      </p>

      <label className="flex items-center gap-3 mb-4 cursor-pointer select-none">
        <input
          type="checkbox"
          checked={enabled}
          onChange={(e) => setEnabled(e.target.checked)}
          disabled={!isAdmin}
          className="w-5 h-5 rounded border-gray-300 text-rose-400 focus:ring-rose-400 cursor-pointer"
        />
        <div>
          <span className="text-sm font-semibold text-ink">Enable parent-teacher messaging</span>
          <p className="text-xs text-muted">
            When disabled, existing message threads are hidden and no new messages can be sent.
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
