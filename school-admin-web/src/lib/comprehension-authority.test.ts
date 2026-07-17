import test from 'node:test';
import assert from 'node:assert/strict';
import {
  AUDIO_AUTHORITY_VERSION,
  hasCurrentAudioAuthority,
  isAllowedAudioRetentionDays,
} from './comprehension-authority.ts';

test('audio retention accepts only the choices shown to administrators', () => {
  for (const days of [7, 30, 90, 365]) {
    assert.equal(isAllowedAudioRetentionDays(days), true);
  }
  for (const days of [0, 14, 730, '30', null]) {
    assert.equal(isAllowedAudioRetentionDays(days), false);
  }
});

test('stored authority must match the current notice and include server evidence', () => {
  assert.equal(hasCurrentAudioAuthority({
    authorityVersion: AUDIO_AUTHORITY_VERSION,
    authorityConfirmedAt: '2026-07-17T00:00:00.000Z',
    retentionDays: 30,
  }), true);
  assert.equal(hasCurrentAudioAuthority({
    authorityVersion: 'old-notice',
    authorityConfirmedAt: '2026-07-17T00:00:00.000Z',
    retentionDays: 30,
  }), false);
  assert.equal(hasCurrentAudioAuthority({
    authorityVersion: AUDIO_AUTHORITY_VERSION,
    retentionDays: 30,
  }), false);
});
