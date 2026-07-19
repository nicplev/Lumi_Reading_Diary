import test from 'node:test';
import assert from 'node:assert/strict';
import {
  comprehensionAudioObjectPath,
  comprehensionAudioUploadObjectPath,
  platformAudioPlaybackIsEnabled,
  schoolAudioPlaybackIsEnabled,
} from './comprehension-audio-policy.ts';

test('derives audio paths from trusted school and log ids', () => {
  assert.equal(
    comprehensionAudioObjectPath('school-a', 'log-1'),
    'schools/school-a/comprehension_audio/log-1.m4a',
  );
  assert.equal(
    comprehensionAudioUploadObjectPath('school-a', 'log-1'),
    'comprehension_audio_uploads/school-a/log-1.m4a',
  );
});

test('playback requires explicit platform and school enablement', () => {
  assert.equal(platformAudioPlaybackIsEnabled({ enabled: true }), true);
  assert.equal(platformAudioPlaybackIsEnabled({ enabled: false }), false);
  assert.equal(platformAudioPlaybackIsEnabled(undefined), false);

  assert.equal(schoolAudioPlaybackIsEnabled({
    settings: { comprehensionRecording: { enabled: true } },
  }), true);
  assert.equal(schoolAudioPlaybackIsEnabled({
    settings: { comprehensionRecording: { enabled: false } },
  }), false);
  assert.equal(schoolAudioPlaybackIsEnabled({}), false);
});
