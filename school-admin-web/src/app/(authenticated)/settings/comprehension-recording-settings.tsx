'use client';

import { useEffect, useState } from 'react';
import { Card } from '@/components/lumi/card';
import { Button } from '@/components/lumi/button';
import { Modal } from '@/components/lumi/modal';
import { Select } from '@/components/lumi/select';
import type {
  ComprehensionRecordingSettings,
  ComprehensionRecordingUpdate,
} from '@/lib/types';
import {
  AUDIO_RETENTION_OPTIONS,
  hasCurrentAudioAuthority,
  type AudioRetentionDays,
} from '@/lib/comprehension-authority';

interface ComprehensionRecordingSettingsSectionProps {
  settings: ComprehensionRecordingSettings | undefined;
  isAdmin: boolean;
  onSave: (settings: ComprehensionRecordingUpdate) => Promise<void>;
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
  const [showAuthorityModal, setShowAuthorityModal] = useState(false);
  const [authorisedBySchool, setAuthorisedBySchool] = useState(false);
  const [familyNoticeConfirmed, setFamilyNoticeConfirmed] = useState(false);
  const [retentionDays, setRetentionDays] = useState<AudioRetentionDays>(30);
  const [modalError, setModalError] = useState<string | null>(null);

  useEffect(() => {
    setEnabled((settings?.enabled ?? false) && hasCurrentAudioAuthority(settings));
    if (typeof settings?.retentionDays === 'number') {
      const saved = AUDIO_RETENTION_OPTIONS.find(
        (option) => option.days === settings.retentionDays,
      );
      if (saved) setRetentionDays(saved.days);
    }
  }, [settings]);

  const handleSave = () => {
    onSave(enabled ? { enabled: true } : { enabled: false });
  };

  const authorityCurrent = hasCurrentAudioAuthority(settings);
  const effectiveStoredEnabled = (settings?.enabled ?? false) && authorityCurrent;
  const dirty = effectiveStoredEnabled !== enabled;

  const requestToggle = (nextEnabled: boolean) => {
    if (!nextEnabled) {
      setEnabled(false);
      return;
    }
    if (authorityCurrent) {
      setEnabled(true);
      return;
    }
    setModalError(null);
    setShowAuthorityModal(true);
  };

  const confirmAuthorityAndEnable = async () => {
    if (!authorisedBySchool || !familyNoticeConfirmed) return;
    setModalError(null);
    try {
      await onSave({
        enabled: true,
        authorityDecision: {
          authorisedBySchool: true,
          familyNoticeConfirmed: true,
          retentionDays,
        },
      });
      setEnabled(true);
      setShowAuthorityModal(false);
    } catch (error) {
      setModalError(
        error instanceof Error ? error.message : 'Lumi could not save this decision.',
      );
    }
  };

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

      {settings?.enabled === true && !authorityCurrent && (
        <div className="mb-4 rounded-lg border border-amber-300 bg-amber-50 px-4 py-3 text-sm text-amber-800">
          Recording cannot collect new audio until a school administrator records
          the school&apos;s authority and retention choice. Turn the option on below to
          review and confirm the decision.
        </div>
      )}

      <label className="flex items-center gap-3 mb-4 cursor-pointer select-none">
        <input
          type="checkbox"
          checked={globallyDisabled ? false : enabled}
          onChange={(e) => requestToggle(e.target.checked)}
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
          {authorityCurrent && settings?.retentionDays && (
            <p className="mt-1 text-xs font-semibold text-ink">
              Saved retention: {settings.retentionDays} days
            </p>
          )}
        </div>
      </label>

      {isAdmin && !globallyDisabled && (
        <div className="flex justify-end">
          <Button onClick={handleSave} loading={saving} disabled={!dirty}>
            Save
          </Button>
        </div>
      )}

      <Modal
        open={showAuthorityModal}
        onClose={() => {
          if (!saving) setShowAuthorityModal(false);
        }}
        title="Before enabling child voice recordings"
        description="Record the school’s authority and choose how quickly Lumi should destroy recordings."
        size="lg"
        footer={(
          <>
            <Button
              variant="outline"
              onClick={() => setShowAuthorityModal(false)}
              disabled={saving}
            >
              Cancel
            </Button>
            <Button
              onClick={confirmAuthorityAndEnable}
              loading={saving}
              disabled={!authorisedBySchool || !familyNoticeConfirmed}
            >
              Confirm and enable
            </Button>
          </>
        )}
      >
        <div className="space-y-5 pb-2 text-sm text-ink">
          <div className="rounded-lg border border-blue-200 bg-blue-50 p-4 text-blue-900">
            Voice recording is optional. Parents may skip it, and families must be
            able to opt out without losing Lumi&apos;s core reading-diary service. This
            record supports the school&apos;s governance process; it is not legal advice
            or a replacement for any notice or consent the school is required to give.
          </div>

          <label className="flex items-start gap-3">
            <input
              type="checkbox"
              checked={authorisedBySchool}
              onChange={(event) => setAuthorisedBySchool(event.target.checked)}
              className="mt-0.5 h-5 w-5 rounded border-gray-300 text-rose-400 focus:ring-rose-400"
            />
            <span>
              I confirm that I am authorised by this school to decide whether Lumi
              may offer optional child voice recording.
            </span>
          </label>

          <label className="flex items-start gap-3">
            <input
              type="checkbox"
              checked={familyNoticeConfirmed}
              onChange={(event) => setFamilyNoticeConfirmed(event.target.checked)}
              className="mt-0.5 h-5 w-5 rounded border-gray-300 text-rose-400 focus:ring-rose-400"
            />
            <span>
              I confirm the school will notify families before collection, explain
              the purpose and retention period, and provide a practical opt-out.
            </span>
          </label>

          <Select
            id="audio-retention-days"
            label="Delete recordings after"
            value={String(retentionDays)}
            onChange={(value) => setRetentionDays(Number(value) as AudioRetentionDays)}
            options={AUDIO_RETENTION_OPTIONS.map((option) => ({
              value: String(option.days),
              label: option.label,
            }))}
          />
          <p className="-mt-3 text-xs text-muted">
            {AUDIO_RETENTION_OPTIONS.find((option) => option.days === retentionDays)?.description}
          </p>

          {modalError && (
            <div className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-red-700">
              {modalError}
            </div>
          )}
        </div>
      </Modal>
    </Card>
  );
}
