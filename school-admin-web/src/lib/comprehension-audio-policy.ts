export const AUDIO_VALIDATION_VERSION = 'ffmpeg-aac-mono-v1';

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object'
    ? value as Record<string, unknown>
    : {};
}

export function comprehensionAudioObjectPath(
  schoolId: string,
  logId: string,
): string {
  return `schools/${schoolId}/comprehension_audio/${logId}.m4a`;
}

export function comprehensionAudioUploadObjectPath(
  schoolId: string,
  logId: string,
): string {
  return `comprehension_audio_uploads/${schoolId}/${logId}.m4a`;
}

export function schoolAudioPlaybackIsEnabled(school: unknown): boolean {
  const schoolData = asRecord(school);
  const settings = asRecord(schoolData.settings);
  const audio = asRecord(settings.comprehensionRecording);
  return audio.enabled === true;
}

export function platformAudioPlaybackIsEnabled(config: unknown): boolean {
  const data = asRecord(config);
  return data.enabled === true;
}
