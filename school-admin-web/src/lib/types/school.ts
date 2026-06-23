export type ReadingLevelSchema =
  | 'none'
  | 'aToZ'
  | 'pmBenchmark'
  | 'lexile'
  | 'numbered'
  | 'namedLevels'
  | 'colouredLevels'
  | 'custom';

export interface School {
  id: string;
  name: string;
  displayName?: string;
  logoUrl?: string;
  primaryColor?: string;
  secondaryColor?: string;
  levelSchema: ReadingLevelSchema;
  customLevels?: string[];
  levelColors?: Record<string, string>;
  termDates: Record<string, Date>;
  quietHours: Record<string, string>;
  timezone: string;
  address?: string;
  contactEmail?: string;
  contactPhone?: string;
  isActive: boolean;
  createdAt: Date;
  createdBy: string;
  settings?: Record<string, unknown>;
  studentCount: number;
  teacherCount: number;
  subscriptionPlan?: string;
  subscriptionExpiry?: Date;
  /** Materialised whole-school access verdict; absent on legacy docs (= active). */
  access?: SchoolAccess;
}

export type SchoolAccessStatus = 'active' | 'suspended';

/**
 * Materialised whole-school access verdict, written server-side by the
 * subscription trigger / rollover cron / off-board wizard. Drives whole-school
 * suspension for staff and families.
 */
export interface SchoolAccess {
  status: SchoolAccessStatus;
  academicYear: number;
  reason?: string;
  updatedAt?: Date;
}

export interface CommentPresetCategory {
  id: string;
  name: string;
  chips: string[];
}

export interface ParentCommentSettings {
  enabled: boolean;
  freeTextEnabled: boolean;
  customPresets: CommentPresetCategory[];
}

// Stored at `schools/{id}.settings.comprehensionRecording`. Drives the
// optional voice-recording step at the end of the parent's reading-log
// wizard. Per-class prompts live on `classes/{id}.settings.comprehensionQuestion`.
export interface ComprehensionRecordingSettings {
  enabled: boolean;
}

export interface AchievementThresholds {
  streak:      [number, number, number, number, number];
  books:       [number, number, number, number, number];
  minutes:     [number, number, number, number, number];
  readingDays: [number, number, number, number];
}

export interface AchievementTierCustomization {
  name?:  string; // undefined = use default name
  color?: string; // CSS hex e.g. "#FF1493"; undefined = use default rarity color
}

export interface AchievementCustomization {
  streak?:      [AchievementTierCustomization, AchievementTierCustomization, AchievementTierCustomization, AchievementTierCustomization, AchievementTierCustomization];
  books?:       [AchievementTierCustomization, AchievementTierCustomization, AchievementTierCustomization, AchievementTierCustomization, AchievementTierCustomization];
  minutes?:     [AchievementTierCustomization, AchievementTierCustomization, AchievementTierCustomization, AchievementTierCustomization, AchievementTierCustomization];
  readingDays?: [AchievementTierCustomization, AchievementTierCustomization, AchievementTierCustomization, AchievementTierCustomization];
}

export const DEFAULT_ACHIEVEMENT_THRESHOLDS: AchievementThresholds = {
  streak:      [5, 10, 20, 50, 100],
  books:       [5, 10, 25, 50, 100],
  minutes:     [300, 600, 1500, 3000, 6000],
  readingDays: [10, 30, 50, 100],
};

export function getReadingLevels(schema: ReadingLevelSchema, customLevels?: string[]): string[] {
  switch (schema) {
    case 'none':
      return [];
    case 'aToZ':
      return 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');
    case 'pmBenchmark':
      return Array.from({ length: 30 }, (_, i) => `${i + 1}`);
    case 'lexile':
      return ['BR', '100L', '200L', '300L', '400L', '500L', '600L', '700L', '800L', '900L', '1000L', '1100L', '1200L', '1300L', '1400L'];
    case 'numbered':
      return Array.from({ length: 100 }, (_, i) => `${i + 1}`);
    case 'namedLevels':
    case 'colouredLevels':
    case 'custom':
      return customLevels ?? [];
  }
}
