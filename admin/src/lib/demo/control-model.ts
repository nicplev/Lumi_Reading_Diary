import { z } from "zod";
import { demoControlDefaults } from "@lumi/server-ops";

const identifierSchema = z
  .string()
  .trim()
  .min(1)
  .max(64)
  .regex(/^[A-Za-z0-9][A-Za-z0-9_-]*$/);

export const demoCommentPresetSchema = z
  .object({
    id: identifierSchema,
    name: z.string().trim().min(1).max(50),
    chips: z
      .array(z.string().trim().min(1).max(100))
      .max(20)
      .refine(
        (chips) => new Set(chips.map((chip) => chip.toLocaleLowerCase())).size === chips.length,
        "Comment options must be unique within a category.",
      ),
  })
  .strict();

const presetListSchema = z
  .array(demoCommentPresetSchema)
  .min(1)
  .max(10)
  .refine(
    (presets) => new Set(presets.map((preset) => preset.id)).size === presets.length,
    "Comment category IDs must be unique.",
  )
  .refine(
    (presets) =>
      new Set(presets.map((preset) => preset.name.toLocaleLowerCase())).size ===
      presets.length,
    "Comment category names must be unique.",
  );

export const demoControlPatchSchema = z
  .object({
    audioRecordingEnabled: z.boolean().optional(),
    parentCommentsEnabled: z.boolean().optional(),
    freeTextCommentsEnabled: z.boolean().optional(),
    messagingEnabled: z.boolean().optional(),
    quickLoggingEnabled: z.boolean().optional(),
    commentPresets: presetListSchema.optional(),
  })
  .strict()
  .refine(
    (value) => Object.values(value).some((entry) => entry !== undefined),
    "At least one demo control must be supplied.",
  );

export type DemoControlPatch = z.infer<typeof demoControlPatchSchema>;
export type DemoCommentPreset = z.infer<typeof demoCommentPresetSchema>;

export interface DemoControlValues {
  audioRecordingEnabled: boolean;
  audioPlatformEnabled: boolean;
  parentCommentsEnabled: boolean;
  freeTextCommentsEnabled: boolean;
  messagingEnabled: boolean;
  quickLoggingEnabled: boolean;
  commentPresets: DemoCommentPreset[];
}

export class DemoControlModelError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "DemoControlModelError";
  }
}

export interface DemoControlTargetFacts {
  projectId: string;
  configuredSchoolId: string;
  immutableSchoolId: string;
  onboardingRequired: boolean;
  onboardingExists: boolean;
  onboardingStatus: unknown;
  schoolExists: boolean;
  schoolIsDemo: unknown;
  credentialIsActiveToday: boolean;
}

export function assertDemoControlTargetFacts(facts: DemoControlTargetFacts): void {
  if (facts.projectId !== "lumi-ninc-au") {
    throw new DemoControlModelError(
      "Safety stop: the super-admin runtime targets the wrong Firebase project.",
    );
  }
  if (facts.configuredSchoolId !== facts.immutableSchoolId) {
    throw new DemoControlModelError(
      "Safety stop: the configured demo tenant is not the immutable demo school.",
    );
  }
  if (
    facts.onboardingRequired &&
    (!facts.onboardingExists || facts.onboardingStatus !== "demo")
  ) {
    throw new DemoControlModelError(
      "Demo controls are available only from an active demo request.",
    );
  }
  if (!facts.schoolExists || facts.schoolIsDemo !== true) {
    throw new DemoControlModelError(
      "Safety stop: the target school is not the isolated synthetic demo tenant.",
    );
  }
  if (!facts.credentialIsActiveToday) {
    throw new DemoControlModelError(
      "Prepare and verify today's demo before changing its live controls.",
    );
  }
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object"
    ? (value as Record<string, unknown>)
    : {};
}

function cloneDefaultPresets(): DemoCommentPreset[] {
  return demoControlDefaults.commentPresets.map((preset) => ({
    id: preset.id,
    name: preset.name,
    chips: [...preset.chips],
  }));
}

function parseStoredPresets(value: unknown): DemoCommentPreset[] {
  const parsed = presetListSchema.safeParse(value);
  if (!parsed.success || parsed.data.length === 0) return cloneDefaultPresets();
  return parsed.data;
}

export function readDemoControlValues(
  schoolData: unknown,
  platformAudioData: unknown,
): DemoControlValues {
  const school = asRecord(schoolData);
  const settings = asRecord(school.settings);
  const audio = asRecord(settings.comprehensionRecording);
  const comments = asRecord(settings.parentComments);
  const messaging = asRecord(settings.messaging);
  const quickLogging = asRecord(settings.quickLogging);
  const platformAudio = asRecord(platformAudioData);

  return {
    audioRecordingEnabled:
      typeof audio.enabled === "boolean"
        ? audio.enabled
        : demoControlDefaults.audioRecordingEnabled,
    audioPlatformEnabled: platformAudio.enabled !== false,
    parentCommentsEnabled:
      typeof comments.enabled === "boolean"
        ? comments.enabled
        : demoControlDefaults.parentCommentsEnabled,
    freeTextCommentsEnabled:
      typeof comments.freeTextEnabled === "boolean"
        ? comments.freeTextEnabled
        : demoControlDefaults.freeTextCommentsEnabled,
    messagingEnabled:
      typeof messaging.enabled === "boolean"
        ? messaging.enabled
        : demoControlDefaults.messagingEnabled,
    quickLoggingEnabled:
      typeof quickLogging.enabled === "boolean"
        ? quickLogging.enabled
        : demoControlDefaults.quickLoggingEnabled,
    commentPresets: parseStoredPresets(comments.customPresets),
  };
}

export interface DemoControlUpdatePlan {
  fields: Record<string, unknown>;
  next: DemoControlValues;
  audit: {
    audioRecordingEnabled: boolean;
    parentCommentsEnabled: boolean;
    freeTextCommentsEnabled: boolean;
    messagingEnabled: boolean;
    quickLoggingEnabled: boolean;
    commentCategoryCount: number;
    commentChipCount: number;
  };
}

/**
 * Builds the exact field-path update accepted by the privileged server route.
 * No request-supplied path, school ID, role or audit identity is used here.
 */
export function buildDemoControlUpdate(
  schoolData: unknown,
  platformAudioData: unknown,
  patch: DemoControlPatch,
  now: Date,
): DemoControlUpdatePlan {
  const current = readDemoControlValues(schoolData, platformAudioData);
  const next: DemoControlValues = {
    ...current,
    ...patch,
    commentPresets: patch.commentPresets
      ? patch.commentPresets.map((preset) => ({
          ...preset,
          chips: [...preset.chips],
        }))
      : current.commentPresets,
  };
  const fields: Record<string, unknown> = {};

  if (patch.audioRecordingEnabled !== undefined) {
    if (patch.audioRecordingEnabled && !current.audioPlatformEnabled) {
      throw new DemoControlModelError(
        "Comprehension recording is disabled by Lumi's platform safety switch.",
      );
    }
    fields["settings.comprehensionRecording"] = {
      enabled: patch.audioRecordingEnabled,
      updatedAt: now,
      // The shared demo gives customers a local record/playback preview only.
      // Deliberately omit real-school authority evidence: Storage Rules and the
      // confirmation callable must continue to reject demo audio uploads.
      demoPreviewOnly: true,
    };
  }

  if (
    patch.parentCommentsEnabled !== undefined ||
    patch.freeTextCommentsEnabled !== undefined ||
    patch.commentPresets !== undefined
  ) {
    fields["settings.parentComments"] = {
      enabled: next.parentCommentsEnabled,
      freeTextEnabled: next.freeTextCommentsEnabled,
      customPresets: next.commentPresets,
      updatedAt: now,
    };
  }

  if (patch.messagingEnabled !== undefined) {
    fields["settings.messaging"] = {
      enabled: next.messagingEnabled,
      updatedAt: now,
    };
  }

  if (patch.quickLoggingEnabled !== undefined) {
    fields["settings.quickLogging"] = {
      enabled: next.quickLoggingEnabled,
      updatedAt: now,
    };
  }

  return {
    fields,
    next,
    audit: {
      audioRecordingEnabled: next.audioRecordingEnabled,
      parentCommentsEnabled: next.parentCommentsEnabled,
      freeTextCommentsEnabled: next.freeTextCommentsEnabled,
      messagingEnabled: next.messagingEnabled,
      quickLoggingEnabled: next.quickLoggingEnabled,
      commentCategoryCount: next.commentPresets.length,
      commentChipCount: next.commentPresets.reduce(
        (total, preset) => total + preset.chips.length,
        0,
      ),
    },
  };
}
