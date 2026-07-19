import test from "node:test";
import assert from "node:assert/strict";
import * as functionsAuthority from "../../../functions/src/audio_authority";
import * as serverOpsAuthority from "../src/audioAuthority";

test("Functions and server-ops use the same audio authority contract", () => {
  assert.equal(
    serverOpsAuthority.AUDIO_AUTHORITY_VERSION,
    functionsAuthority.AUDIO_AUTHORITY_VERSION
  );
  assert.deepEqual(
    serverOpsAuthority.AUDIO_RETENTION_CHOICES,
    functionsAuthority.AUDIO_RETENTION_CHOICES
  );
  assert.deepEqual(
    serverOpsAuthority.LEGACY_AUDIO_RETENTION_CHOICES,
    functionsAuthority.LEGACY_AUDIO_RETENTION_CHOICES
  );

  const fixtures: unknown[] = [
    null,
    {},
    { settings: { comprehensionRecording: { enabled: true } } },
    {
      settings: {
        comprehensionRecording: {
          enabled: true,
          authorityVersion: functionsAuthority.AUDIO_AUTHORITY_VERSION,
          authorityConfirmedAt: new Date("2026-07-17T00:00:00Z"),
          retentionDays: 30,
        },
      },
    },
    {
      settings: {
        comprehensionRecording: { enabled: true, retentionDays: 7 },
      },
    },
    {
      settings: {
        comprehensionRecording: { enabled: false, retentionDays: 365 },
      },
    },
  ];

  for (const school of fixtures) {
    assert.equal(
      serverOpsAuthority.schoolAudioCollectionIsAuthorised(school),
      functionsAuthority.schoolAudioCollectionIsAuthorised(school)
    );
    assert.equal(
      serverOpsAuthority.schoolAudioPlaybackIsEnabled(school),
      functionsAuthority.schoolAudioPlaybackIsEnabled(school)
    );
    assert.deepEqual(
      serverOpsAuthority.retentionDecisionForSchool(school, 90),
      functionsAuthority.retentionDecisionForSchool(school, 90)
    );
  }
});

test("seven days is legacy cleanup compatibility, not new collection authority", () => {
  assert.equal(serverOpsAuthority.isAllowedSchoolAudioRetention(7), false);
  assert.deepEqual(
    serverOpsAuthority.retentionDecisionForSchool(
      { settings: { comprehensionRecording: { retentionDays: 7 } } },
      90
    ),
    { days: 7, source: "legacySchool" }
  );
});
