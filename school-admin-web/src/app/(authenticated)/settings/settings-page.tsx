'use client';

import { useState, useEffect } from 'react';
import { PageHeader } from '@/components/lumi/page-header';
import { Icon } from '@/components/lumi/icon';
import { Card } from '@/components/lumi/card';
import { Input } from '@/components/lumi/input';
import { Select } from '@/components/lumi/select';
import { Button } from '@/components/lumi/button';
import { Badge } from '@/components/lumi/badge';
import { Skeleton } from '@/components/lumi/skeleton';
import { Tabs } from '@/components/lumi/tabs';
import { ConfirmDialog } from '@/components/lumi/confirm-dialog';
import { useToast } from '@/components/lumi/toast';
import { useAuth } from '@/lib/auth/auth-context';
import { useSchool, useUpdateSchool } from '@/lib/hooks/use-school';
import { getReadingLevels } from '@/lib/types';
import type { ReadingLevelSchema, ParentCommentSettings, AchievementCustomization } from '@/lib/types';
import { ParentCommentSettingsSection } from './parent-comment-settings';
import { AchievementThresholdSettings } from './achievement-threshold-settings';
import type { AchievementThresholds } from '@/lib/types';

const LEVEL_SCHEMAS: { value: ReadingLevelSchema; label: string; description: string }[] = [
  { value: 'none', label: 'None', description: 'No reading levels' },
  { value: 'aToZ', label: 'A to Z', description: 'Letters A through Z' },
  { value: 'pmBenchmark', label: 'PM Benchmark', description: 'Levels 1-30' },
  { value: 'lexile', label: 'Lexile', description: 'BR, 100L-1400L' },
  { value: 'numbered', label: 'Numbered', description: 'Levels 1-100' },
  { value: 'namedLevels', label: 'Named Levels', description: 'Custom named levels' },
  { value: 'colouredLevels', label: 'Coloured Levels', description: 'Custom colour-based levels' },
  { value: 'custom', label: 'Custom', description: 'Define your own levels' },
];

const TIMEZONES = [
  'Pacific/Auckland', 'Australia/Sydney', 'Australia/Melbourne', 'Australia/Brisbane',
  'Australia/Adelaide', 'Australia/Perth', 'Asia/Singapore', 'Asia/Tokyo',
  'Europe/London', 'Europe/Paris', 'America/New_York', 'America/Chicago',
  'America/Denver', 'America/Los_Angeles', 'UTC',
];

const SETTINGS_TABS = [
  { id: 'school', label: 'School', icon: <Icon name="apartment" size={16} /> },
  { id: 'academic', label: 'Academic', icon: <Icon name="menu_book" size={16} /> },
  { id: 'parent-app', label: 'Parent App', icon: <Icon name="smartphone" size={16} /> },
  { id: 'achievements', label: 'Achievements', icon: <Icon name="military_tech" size={16} /> },
];

export function SettingsPage() {
  const { toast } = useToast();
  const { user } = useAuth();
  const { data: school, isLoading } = useSchool();
  const updateSchool = useUpdateSchool();

  const isAdmin = user?.role === 'schoolAdmin';
  const [activeTab, setActiveTab] = useState('school');

  // School info
  const [name, setName] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [address, setAddress] = useState('');
  const [contactEmail, setContactEmail] = useState('');
  const [contactPhone, setContactPhone] = useState('');
  const [timezone, setTimezone] = useState('');

  // Reading levels
  const [levelSchema, setLevelSchema] = useState<ReadingLevelSchema>('aToZ');
  const [customLevels, setCustomLevels] = useState('');
  const [showSchemaConfirm, setShowSchemaConfirm] = useState(false);

  // Term dates
  const [termDates, setTermDates] = useState<Record<string, string>>({});

  // Quiet hours
  const [quietStart, setQuietStart] = useState('');
  const [quietEnd, setQuietEnd] = useState('');

  // Per-section saving states
  const [savingInfo, setSavingInfo] = useState(false);
  const [savingLevels, setSavingLevels] = useState(false);
  const [savingTerms, setSavingTerms] = useState(false);
  const [savingQuiet, setSavingQuiet] = useState(false);
  const [savingComments, setSavingComments] = useState(false);
  const [savingAchievements, setSavingAchievements] = useState(false);

  useEffect(() => {
    if (school) {
      setName(school.name);
      setDisplayName(school.displayName ?? '');
      setAddress(school.address ?? '');
      setContactEmail(school.contactEmail ?? '');
      setContactPhone(school.contactPhone ?? '');
      setTimezone(school.timezone);
      setLevelSchema(school.levelSchema);
      setCustomLevels(school.customLevels?.join(', ') ?? '');
      setTermDates(school.termDates ?? {});
      setQuietStart(school.quietHours?.start ?? '');
      setQuietEnd(school.quietHours?.end ?? '');
    }
  }, [school]);

  const handleSaveInfo = async () => {
    setSavingInfo(true);
    try {
      await updateSchool.mutateAsync({
        name: name.trim(),
        displayName: displayName.trim() || undefined,
        address: address.trim(),
        contactEmail: contactEmail.trim(),
        contactPhone: contactPhone.trim(),
        timezone,
      });
      toast('School info updated', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to save', 'error');
    } finally {
      setSavingInfo(false);
    }
  };

  const needsCustomLevels = ['namedLevels', 'colouredLevels', 'custom'].includes(levelSchema);
  const parsedCustomLevels = customLevels.split(',').map((l) => l.trim()).filter(Boolean);

  const handleSaveLevels = async () => {
    if (needsCustomLevels && parsedCustomLevels.length === 0) {
      toast('Please enter at least one custom level', 'error');
      return;
    }
    if (school && levelSchema !== school.levelSchema) {
      setShowSchemaConfirm(true);
      return;
    }
    await doSaveLevels();
  };

  const doSaveLevels = async () => {
    setSavingLevels(true);
    setShowSchemaConfirm(false);
    try {
      await updateSchool.mutateAsync({
        levelSchema,
        customLevels: needsCustomLevels ? parsedCustomLevels : undefined,
      });
      toast('Reading level schema updated', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to save', 'error');
    } finally {
      setSavingLevels(false);
    }
  };

  const handleSaveTermDates = async () => {
    setSavingTerms(true);
    try {
      await updateSchool.mutateAsync({ termDates });
      toast('Term dates updated', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to save', 'error');
    } finally {
      setSavingTerms(false);
    }
  };

  const handleSaveQuietHours = async () => {
    setSavingQuiet(true);
    try {
      await updateSchool.mutateAsync({
        quietHours: { start: quietStart, end: quietEnd },
      });
      toast('Quiet hours updated', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to save', 'error');
    } finally {
      setSavingQuiet(false);
    }
  };

  const handleSaveComments = async (commentSettings: ParentCommentSettings) => {
    setSavingComments(true);
    try {
      await updateSchool.mutateAsync({
        parentCommentSettings: commentSettings,
      });
      toast('Parent comment settings updated', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to save', 'error');
    } finally {
      setSavingComments(false);
    }
  };

  const handleSaveAchievements = async (thresholds: AchievementThresholds, customization: AchievementCustomization) => {
    setSavingAchievements(true);
    try {
      await updateSchool.mutateAsync({ achievementThresholds: thresholds, achievementCustomization: customization });
      toast('Achievement settings updated', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to save', 'error');
    } finally {
      setSavingAchievements(false);
    }
  };

  const updateTermDate = (key: string, value: string) => {
    setTermDates((prev) => ({ ...prev, [key]: value }));
  };

  const previewLevels = getReadingLevels(levelSchema, parsedCustomLevels);

  if (isLoading) {
    return (
      <div>
        <PageHeader title="Settings" description="School configuration" />
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
          {Array.from({ length: 4 }).map((_, i) => (
            <div key={i} className="bg-surface rounded-[var(--radius-lg)] shadow-card p-5">
              <Skeleton className="h-4 w-20 mb-3" />
              <Skeleton className="h-8 w-16" />
            </div>
          ))}
        </div>
        <div className="border-b border-divider mb-6">
          <div className="flex gap-6 pb-3">
            {Array.from({ length: 3 }).map((_, i) => (
              <Skeleton key={i} className="h-4 w-20" />
            ))}
          </div>
        </div>
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {Array.from({ length: 2 }).map((_, i) => (
            <div key={i} className="bg-surface rounded-[var(--radius-lg)] shadow-card p-6">
              <Skeleton className="h-5 w-32 mb-4" />
              <Skeleton className="h-10 w-full mb-3" />
              <Skeleton className="h-10 w-full" />
            </div>
          ))}
        </div>
      </div>
    );
  }

  return (
    <div>
      <PageHeader
        title="Settings"
        description="School configuration"
        action={
          school ? (
            <div className="flex items-center gap-3">
              <span className="inline-flex items-center gap-1.5 text-sm text-text-secondary">
                <Icon name="group" size={16} />
                <span className="font-semibold text-charcoal">{school.studentCount}</span> students
              </span>
              <span className="w-px h-4 bg-divider" />
              <span className="inline-flex items-center gap-1.5 text-sm text-text-secondary">
                <Icon name="person" size={16} />
                <span className="font-semibold text-charcoal">{school.teacherCount}</span> teachers
              </span>
            </div>
          ) : undefined
        }
      />

      {/* Tab Navigation */}
      <Tabs tabs={SETTINGS_TABS} activeTab={activeTab} onChange={setActiveTab} />

      {/* School Tab */}
      {activeTab === 'school' && (
        <Card>
          <h2 className="text-lg font-bold text-charcoal mb-4">School Information</h2>
          <div className="space-y-4">
            <Input label="School Name" value={name} onChange={(e) => setName(e.target.value)} disabled={!isAdmin} />
            <Input
              label="Display Name"
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              disabled={!isAdmin}
              placeholder="Optional — shown in sidebar and headers"
            />
            <Input label="Address" value={address} onChange={(e) => setAddress(e.target.value)} disabled={!isAdmin} />
            <div className="grid grid-cols-2 gap-4">
              <Input label="Contact Email" type="email" value={contactEmail} onChange={(e) => setContactEmail(e.target.value)} disabled={!isAdmin} placeholder="Shown to parents in the app" />
              <Input label="Contact Phone" value={contactPhone} onChange={(e) => setContactPhone(e.target.value)} disabled={!isAdmin} placeholder="Shown to parents in the app" />
            </div>
            <Select
              label="Timezone"
              options={TIMEZONES.map((tz) => ({ value: tz, label: tz.replace(/_/g, ' ') }))}
              value={timezone}
              onChange={setTimezone}
              disabled={!isAdmin}
            />
            {isAdmin && (
              <div className="flex justify-end">
                <Button onClick={handleSaveInfo} loading={savingInfo} disabled={!name.trim()}>
                  Save Info
                </Button>
              </div>
            )}
          </div>
        </Card>
      )}

      {/* Academic Tab */}
      {activeTab === 'academic' && (
        <>
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {/* Reading Level Schema */}
            <Card>
              <h2 className="text-lg font-bold text-charcoal mb-4">Reading Level Schema</h2>
              <div className="space-y-4">
                <Select
                  label="Schema"
                  options={LEVEL_SCHEMAS.map((s) => ({ value: s.value, label: `${s.label} — ${s.description}` }))}
                  value={levelSchema}
                  onChange={(v) => setLevelSchema(v as ReadingLevelSchema)}
                  disabled={!isAdmin}
                />
                {needsCustomLevels && (
                  <Input
                    label="Custom Levels (comma-separated)"
                    value={customLevels}
                    onChange={(e) => setCustomLevels(e.target.value)}
                    placeholder="e.g. Magenta, Red, Yellow, Blue, Green"
                    disabled={!isAdmin}
                  />
                )}
                {previewLevels.length > 0 && (
                  <div>
                    <p className="text-sm font-semibold text-charcoal mb-2">Preview ({previewLevels.length} levels)</p>
                    <div className="flex flex-wrap gap-1.5">
                      {previewLevels.slice(0, 30).map((level) => (
                        <Badge key={level} variant="default">{level}</Badge>
                      ))}
                      {previewLevels.length > 30 && (
                        <Badge variant="default">+{previewLevels.length - 30} more</Badge>
                      )}
                    </div>
                  </div>
                )}
                {isAdmin && (
                  <div className="flex justify-end">
                    <Button onClick={handleSaveLevels} loading={savingLevels}>
                      Save Schema
                    </Button>
                  </div>
                )}
              </div>
            </Card>

            {/* Term Dates */}
            <Card>
              <h2 className="text-lg font-bold text-charcoal mb-1">Term Dates</h2>
              <p className="text-sm text-text-secondary mb-4">Used for analytics, reporting periods, and term-based comparisons.</p>
              <div className="space-y-4">
                {[1, 2, 3, 4].map((term) => (
                  <div key={term} className="grid grid-cols-2 gap-4">
                    <Input
                      label={`Term ${term} Start`}
                      type="date"
                      value={termDates[`term${term}Start`] ? termDates[`term${term}Start`].split('T')[0] : ''}
                      onChange={(e) => updateTermDate(`term${term}Start`, e.target.value)}
                      disabled={!isAdmin}
                    />
                    <Input
                      label={`Term ${term} End`}
                      type="date"
                      value={termDates[`term${term}End`] ? termDates[`term${term}End`].split('T')[0] : ''}
                      onChange={(e) => updateTermDate(`term${term}End`, e.target.value)}
                      disabled={!isAdmin}
                    />
                  </div>
                ))}
                {isAdmin && (
                  <div className="flex justify-end">
                    <Button onClick={handleSaveTermDates} loading={savingTerms}>
                      Save Term Dates
                    </Button>
                  </div>
                )}
              </div>
            </Card>
          </div>

          {/* Schema Change Confirmation Dialog */}
          <ConfirmDialog
            open={showSchemaConfirm}
            onClose={() => setShowSchemaConfirm(false)}
            onConfirm={doSaveLevels}
            title="Change Reading Level Schema?"
            description="Changing the reading level schema may make existing student levels invalid. Students currently assigned levels under the old schema will keep their values, but they may not match the new level options. Are you sure you want to continue?"
            confirmLabel="Change Schema"
            variant="warning"
            loading={savingLevels}
          />
        </>
      )}

      {/* Achievements Tab */}
      {activeTab === 'achievements' && (
        <AchievementThresholdSettings
          thresholds={school?.settings?.achievementThresholds as AchievementThresholds | undefined}
          customization={school?.settings?.achievementCustomization as AchievementCustomization | undefined}
          isAdmin={isAdmin}
          onSave={handleSaveAchievements}
          saving={savingAchievements}
        />
      )}

      {/* Parent App Tab */}
      {activeTab === 'parent-app' && (
        <div className="space-y-6">
          {/* Quiet Hours */}
          <Card className="max-w-sm">
            <h2 className="text-lg font-bold text-charcoal mb-1">Notification Quiet Hours</h2>
            <p className="text-sm text-text-secondary mb-4">
              Notifications will not be sent during these hours.
            </p>
            <div className="grid grid-cols-2 gap-4">
              <Input
                label="Start Time"
                type="time"
                value={quietStart}
                onChange={(e) => setQuietStart(e.target.value)}
                disabled={!isAdmin}
              />
              <Input
                label="End Time"
                type="time"
                value={quietEnd}
                onChange={(e) => setQuietEnd(e.target.value)}
                disabled={!isAdmin}
              />
            </div>
            {isAdmin && (
              <div className="flex justify-end mt-4">
                <Button onClick={handleSaveQuietHours} loading={savingQuiet}>
                  Save Quiet Hours
                </Button>
              </div>
            )}
          </Card>

          {/* Parent Comments */}
          <ParentCommentSettingsSection
            settings={school?.settings?.parentComments as ParentCommentSettings | undefined}
            isAdmin={isAdmin}
            onSave={handleSaveComments}
            saving={savingComments}
          />
        </div>
      )}
    </div>
  );
}
