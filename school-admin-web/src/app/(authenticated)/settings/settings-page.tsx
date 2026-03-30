'use client';

import { useState, useEffect } from 'react';
import { PageHeader } from '@/components/lumi/page-header';
import { Card } from '@/components/lumi/card';
import { Input } from '@/components/lumi/input';
import { Select } from '@/components/lumi/select';
import { Button } from '@/components/lumi/button';
import { Badge } from '@/components/lumi/badge';
import { Skeleton } from '@/components/lumi/skeleton';
import { useToast } from '@/components/lumi/toast';
import { useAuth } from '@/lib/auth/auth-context';
import { useSchool, useUpdateSchool } from '@/lib/hooks/use-school';
import { getReadingLevels } from '@/lib/types';
import type { ReadingLevelSchema } from '@/lib/types';

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

export function SettingsPage() {
  const { toast } = useToast();
  const { user } = useAuth();
  const { data: school, isLoading } = useSchool();
  const updateSchool = useUpdateSchool();

  const isAdmin = user?.role === 'schoolAdmin';

  // School info
  const [name, setName] = useState('');
  const [address, setAddress] = useState('');
  const [contactEmail, setContactEmail] = useState('');
  const [contactPhone, setContactPhone] = useState('');
  const [timezone, setTimezone] = useState('');

  // Reading levels
  const [levelSchema, setLevelSchema] = useState<ReadingLevelSchema>('aToZ');
  const [customLevels, setCustomLevels] = useState('');

  // Term dates
  const [termDates, setTermDates] = useState<Record<string, string>>({});

  // Quiet hours
  const [quietStart, setQuietStart] = useState('');
  const [quietEnd, setQuietEnd] = useState('');

  useEffect(() => {
    if (school) {
      setName(school.name);
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
    try {
      await updateSchool.mutateAsync({
        name: name.trim(),
        address: address.trim(),
        contactEmail: contactEmail.trim(),
        contactPhone: contactPhone.trim(),
        timezone,
      });
      toast('School info updated', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to save', 'error');
    }
  };

  const handleSaveLevels = async () => {
    try {
      const needsCustom = ['namedLevels', 'colouredLevels', 'custom'].includes(levelSchema);
      const levels = needsCustom
        ? customLevels.split(',').map((l) => l.trim()).filter(Boolean)
        : undefined;

      await updateSchool.mutateAsync({
        levelSchema,
        customLevels: levels,
      });
      toast('Reading level schema updated', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to save', 'error');
    }
  };

  const handleSaveTermDates = async () => {
    try {
      await updateSchool.mutateAsync({ termDates });
      toast('Term dates updated', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to save', 'error');
    }
  };

  const handleSaveQuietHours = async () => {
    try {
      await updateSchool.mutateAsync({
        quietHours: { start: quietStart, end: quietEnd },
      });
      toast('Quiet hours updated', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to save', 'error');
    }
  };

  const updateTermDate = (key: string, value: string) => {
    setTermDates((prev) => ({ ...prev, [key]: value }));
  };

  const previewLevels = getReadingLevels(
    levelSchema,
    customLevels.split(',').map((l) => l.trim()).filter(Boolean)
  );

  if (isLoading) {
    return (
      <div>
        <PageHeader title="Settings" description="School configuration" />
        <div className="space-y-6 max-w-2xl">
          {Array.from({ length: 3 }).map((_, i) => (
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
      <PageHeader title="Settings" description="School configuration" />

      <div className="space-y-6 max-w-2xl">
        {/* School Info */}
        <Card>
          <h2 className="text-lg font-bold text-charcoal mb-4">School Information</h2>
          <div className="space-y-4">
            <Input label="School Name" value={name} onChange={(e) => setName(e.target.value)} disabled={!isAdmin} />
            <Input label="Address" value={address} onChange={(e) => setAddress(e.target.value)} disabled={!isAdmin} />
            <div className="grid grid-cols-2 gap-4">
              <Input label="Contact Email" type="email" value={contactEmail} onChange={(e) => setContactEmail(e.target.value)} disabled={!isAdmin} />
              <Input label="Contact Phone" value={contactPhone} onChange={(e) => setContactPhone(e.target.value)} disabled={!isAdmin} />
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
                <Button onClick={handleSaveInfo} loading={updateSchool.isPending} disabled={!name.trim()}>
                  Save Info
                </Button>
              </div>
            )}
          </div>
        </Card>

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

            {['namedLevels', 'colouredLevels', 'custom'].includes(levelSchema) && (
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
                <Button onClick={handleSaveLevels} loading={updateSchool.isPending}>
                  Save Schema
                </Button>
              </div>
            )}
          </div>
        </Card>

        {/* Term Dates */}
        <Card>
          <h2 className="text-lg font-bold text-charcoal mb-4">Term Dates</h2>
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
                <Button onClick={handleSaveTermDates} loading={updateSchool.isPending}>
                  Save Term Dates
                </Button>
              </div>
            )}
          </div>
        </Card>

        {/* Quiet Hours */}
        <Card>
          <h2 className="text-lg font-bold text-charcoal mb-4">Notification Quiet Hours</h2>
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
              <Button onClick={handleSaveQuietHours} loading={updateSchool.isPending}>
                Save Quiet Hours
              </Button>
            </div>
          )}
        </Card>

        {/* School Stats (read-only) */}
        {school && (
          <Card>
            <h2 className="text-lg font-bold text-charcoal mb-4">School Overview</h2>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <p className="text-sm text-text-secondary">Students</p>
                <p className="text-2xl font-bold text-charcoal">{school.studentCount}</p>
              </div>
              <div>
                <p className="text-sm text-text-secondary">Teachers</p>
                <p className="text-2xl font-bold text-charcoal">{school.teacherCount}</p>
              </div>
              <div>
                <p className="text-sm text-text-secondary">Plan</p>
                <p className="text-sm font-semibold text-charcoal">{school.subscriptionPlan ?? 'Free'}</p>
              </div>
              <div>
                <p className="text-sm text-text-secondary">Status</p>
                <Badge variant={school.isActive ? 'success' : 'error'}>
                  {school.isActive ? 'Active' : 'Inactive'}
                </Badge>
              </div>
            </div>
          </Card>
        )}
      </div>
    </div>
  );
}
