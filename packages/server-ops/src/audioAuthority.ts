// MIRROR of functions/src/audio_authority.ts.
// Keep this file zero-import and update the parity test with every change.

export const AUDIO_AUTHORITY_VERSION = "school-audio-v1-2026-07-17";
export const AUDIO_RETENTION_CHOICES = [30, 90, 365] as const;
export const LEGACY_AUDIO_RETENTION_CHOICES = [7] as const;

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object"
    ? value as Record<string, unknown>
    : {};
}

export function isAllowedSchoolAudioRetention(value: unknown): value is number {
  return typeof value === "number" &&
    Number.isInteger(value) &&
    (AUDIO_RETENTION_CHOICES as readonly number[]).includes(value);
}

function isLegacySchoolAudioRetention(value: unknown): value is number {
  return typeof value === "number" &&
    Number.isInteger(value) &&
    (LEGACY_AUDIO_RETENTION_CHOICES as readonly number[]).includes(value);
}

export function schoolAudioCollectionIsAuthorised(school: unknown): boolean {
  const schoolData = asRecord(school);
  const settings = asRecord(schoolData.settings);
  const audio = asRecord(settings.comprehensionRecording);
  return audio.enabled === true &&
    audio.authorityVersion === AUDIO_AUTHORITY_VERSION &&
    audio.authorityConfirmedAt != null &&
    isAllowedSchoolAudioRetention(audio.retentionDays);
}

export function schoolAudioPlaybackIsEnabled(school: unknown): boolean {
  const schoolData = asRecord(school);
  const settings = asRecord(schoolData.settings);
  const audio = asRecord(settings.comprehensionRecording);
  return audio.enabled === true;
}

export type AudioRetentionSource = "school" | "legacySchool" | "fallback";

export function retentionDecisionForSchool(
  school: unknown,
  legacyDefaultDays: number
): {days: number; source: AudioRetentionSource} {
  const schoolData = asRecord(school);
  const settings = asRecord(schoolData.settings);
  const audio = asRecord(settings.comprehensionRecording);
  if (isAllowedSchoolAudioRetention(audio.retentionDays)) {
    return {days: audio.retentionDays, source: "school"};
  }
  if (isLegacySchoolAudioRetention(audio.retentionDays)) {
    return {days: audio.retentionDays, source: "legacySchool"};
  }
  return {days: legacyDefaultDays, source: "fallback"};
}

export function retentionDaysForSchool(
  school: unknown,
  legacyDefaultDays: number
): number {
  return retentionDecisionForSchool(school, legacyDefaultDays).days;
}
