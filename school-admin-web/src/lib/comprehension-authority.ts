export const AUDIO_AUTHORITY_VERSION = 'school-audio-v1-2026-07-17';

export const AUDIO_RETENTION_OPTIONS = [
  {
    days: 7,
    label: '7 days',
    description: 'Shortest storage period; best for one-off teacher review.',
  },
  {
    days: 30,
    label: '30 days — recommended',
    description: 'Enough time for ordinary review while minimising child voice storage.',
  },
  {
    days: 90,
    label: '90 days',
    description: 'Keeps recordings for roughly one school term.',
  },
  {
    days: 365,
    label: '365 days',
    description: 'School-year retention; choose only where the school has a documented need.',
  },
] as const;

export type AudioRetentionDays = (typeof AUDIO_RETENTION_OPTIONS)[number]['days'];

export interface AudioAuthorityDecision {
  authorisedBySchool: true;
  familyNoticeConfirmed: true;
  retentionDays: AudioRetentionDays;
}

export function isAllowedAudioRetentionDays(value: unknown): value is AudioRetentionDays {
  return AUDIO_RETENTION_OPTIONS.some((option) => option.days === value);
}

export function hasCurrentAudioAuthority(value: unknown): boolean {
  if (!value || typeof value !== 'object') return false;
  const settings = value as Record<string, unknown>;
  return settings.authorityVersion === AUDIO_AUTHORITY_VERSION &&
    isAllowedAudioRetentionDays(settings.retentionDays) &&
    settings.authorityConfirmedAt != null;
}
