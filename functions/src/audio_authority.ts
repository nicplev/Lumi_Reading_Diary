export const AUDIO_AUTHORITY_VERSION = "school-audio-v1-2026-07-17";
export const AUDIO_RETENTION_CHOICES = [7, 30, 90, 365] as const;

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" ?
    value as Record<string, unknown> : {};
}

export function isAllowedSchoolAudioRetention(value: unknown): value is number {
  return typeof value === "number" &&
    Number.isInteger(value) &&
    (AUDIO_RETENTION_CHOICES as readonly number[]).includes(value);
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

export function retentionDaysForSchool(
  school: unknown,
  legacyDefaultDays: number
): number {
  const schoolData = asRecord(school);
  const settings = asRecord(schoolData.settings);
  const audio = asRecord(settings.comprehensionRecording);
  return isAllowedSchoolAudioRetention(audio.retentionDays) ?
    audio.retentionDays : legacyDefaultDays;
}
