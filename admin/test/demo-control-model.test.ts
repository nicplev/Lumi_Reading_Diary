import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import test from "node:test";
import {
  assertDemoControlTargetFacts,
  buildDemoControlUpdate,
  DemoControlModelError,
  demoControlPatchSchema,
  readDemoControlValues,
} from "../src/lib/demo/control-model";

const now = new Date("2026-07-19T01:00:00.000Z");
const school = {
  isDemo: true,
  settings: {
    comprehensionRecording: { enabled: false },
    parentComments: {
      enabled: true,
      freeTextEnabled: true,
      customPresets: [
        { id: "existing", name: "Existing", chips: ["Keep going!"] },
      ],
    },
    messaging: { enabled: true },
    quickLogging: { enabled: true },
  },
};

test("control schema is strict and bounds custom comment data", () => {
  assert.equal(
    demoControlPatchSchema.safeParse({ messagingEnabled: false }).success,
    true,
  );
  assert.equal(demoControlPatchSchema.safeParse({}).success, false);
  assert.equal(
    demoControlPatchSchema.safeParse({ messagingEnabled: true, schoolId: "other" })
      .success,
    false,
  );
  assert.equal(
    demoControlPatchSchema.safeParse({ commentPresets: [] }).success,
    false,
  );
  assert.equal(
    demoControlPatchSchema.safeParse({
      commentPresets: [
        { id: "one", name: "One", chips: ["Same", "same"] },
      ],
    }).success,
    false,
  );
  assert.equal(
    demoControlPatchSchema.safeParse({
      commentPresets: Array.from({ length: 11 }, (_, index) => ({
        id: `category-${index}`,
        name: `Category ${index}`,
        chips: [],
      })),
    }).success,
    false,
  );
});

test("real demo settings update only allowlisted field paths and redact audit chips", () => {
  const patch = demoControlPatchSchema.parse({
    audioRecordingEnabled: true,
    parentCommentsEnabled: true,
    freeTextCommentsEnabled: false,
    messagingEnabled: false,
    quickLoggingEnabled: false,
    commentPresets: [
      { id: "demo", name: "Demo category", chips: ["Private operator text"] },
    ],
  });
  const update = buildDemoControlUpdate(
    school,
    { enabled: true },
    patch,
    now,
  );

  assert.deepEqual(Object.keys(update.fields).sort(), [
    "settings.comprehensionRecording",
    "settings.messaging",
    "settings.parentComments",
    "settings.quickLogging",
  ]);
  const audio = update.fields["settings.comprehensionRecording"] as Record<
    string,
    unknown
  >;
  assert.deepEqual(Object.keys(audio).sort(), [
    "demoPreviewOnly",
    "enabled",
    "updatedAt",
  ]);
  assert.equal(audio.enabled, true);
  assert.equal(audio.demoPreviewOnly, true);
  assert.equal("authorityVersion" in audio, false);
  assert.equal("authorisedBySchool" in audio, false);
  assert.equal(JSON.stringify(update.audit).includes("Private operator text"), false);
  assert.equal(update.audit.commentCategoryCount, 1);
  assert.equal(update.audit.commentChipCount, 1);
});

test("platform audio safety switch remains authoritative", () => {
  assert.throws(
    () =>
      buildDemoControlUpdate(
        school,
        { enabled: false },
        { audioRecordingEnabled: true },
        now,
      ),
    DemoControlModelError,
  );
});

test("target guard refuses wrong project, tenant, request, marker or day state", () => {
  const valid = {
    projectId: "lumi-ninc-au",
    configuredSchoolId: "lumi_demo_primary_school",
    immutableSchoolId: "lumi_demo_primary_school",
    onboardingRequired: true,
    onboardingExists: true,
    onboardingStatus: "demo",
    schoolExists: true,
    schoolIsDemo: true,
    credentialIsActiveToday: true,
  };
  assert.doesNotThrow(() => assertDemoControlTargetFacts(valid));

  for (const invalid of [
    { projectId: "another-project" },
    { configuredSchoolId: "another-school" },
    { onboardingStatus: "active" },
    { schoolIsDemo: false },
    { credentialIsActiveToday: false },
  ]) {
    assert.throws(
      () => assertDemoControlTargetFacts({ ...valid, ...invalid }),
      DemoControlModelError,
    );
  }

  assert.doesNotThrow(() =>
    assertDemoControlTargetFacts({
      ...valid,
      onboardingRequired: false,
      onboardingExists: false,
      onboardingStatus: undefined,
    }),
  );
});

test("missing stored controls resolve to the colourful populated defaults", () => {
  const controls = readDemoControlValues({ settings: {} }, { enabled: true });
  assert.equal(controls.parentCommentsEnabled, true);
  assert.equal(controls.freeTextCommentsEnabled, true);
  assert.equal(controls.messagingEnabled, true);
  assert.equal(controls.quickLoggingEnabled, true);
  assert.equal(controls.commentPresets.length, 3);
  assert.ok(controls.commentPresets.every((preset) => preset.chips.length === 4));
});

test("routes independently enforce session, same-origin, validation and limits", () => {
  for (const path of [
    "admin/src/app/api/demo/settings/route.ts",
    "admin/src/app/api/onboarding/[id]/demo-controls/route.ts",
  ]) {
    const source = readFileSync(resolve(path), "utf8");
    for (const invariant of [
      "verifySession()",
      "assertSameOrigin(request)",
      "demoControlPatchSchema.parse",
      "consumeDemoRouteLimits",
      '"cache-control": "no-store, max-age=0"',
    ]) {
      assert.equal(source.includes(invariant), true, `${path} lacks ${invariant}`);
    }
  }

});

test("demo audio stays a local preview and cannot enter upload paths", () => {
  const widget = readFileSync(
    resolve("lib/screens/parent/widgets/comprehension_recording_step.dart"),
    "utf8",
  );
  const detailedFlow = readFileSync(
    resolve("lib/screens/parent/log_reading_screen.dart"),
    "utf8",
  );
  const quickFlow = readFileSync(
    resolve("lib/screens/parent/reading_success_screen.dart"),
    "utf8",
  );
  const storageRules = readFileSync(resolve("storage.rules"), "utf8");
  const callableGuard = readFileSync(
    resolve("functions/src/read_only_guard.ts"),
    "utf8",
  );

  assert.equal(widget.includes("Demo preview — try recording and playback"), true);
  assert.equal(
    detailedFlow.includes("discardComprehensionRecordingPreview(recording)"),
    true,
  );
  assert.equal(
    quickFlow.includes("discardComprehensionRecordingPreview(recording)"),
    true,
  );
  assert.equal(storageRules.includes("&& !isDemoAccount()"), true);
  assert.equal(callableGuard.includes("token?.demoAccount === true"), true);
});
