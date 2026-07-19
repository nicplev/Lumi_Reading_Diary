export function buildDemoSchoolPlanData(now?: Date): unknown;

export const DEMO_CONTROL_DEFAULTS: {
  audioRecordingEnabled: boolean;
  parentCommentsEnabled: boolean;
  freeTextCommentsEnabled: boolean;
  messagingEnabled: boolean;
  quickLoggingEnabled: boolean;
  commentPresets: Array<{ id: string; name: string; chips: string[] }>;
};

export const DEMO_STUDENT_CHARACTER_IDS: string[];

export const DEMO_SCHOOL_CONSTANTS: {
  schoolId: string;
  schoolName: string;
  timezone: string;
  retiredIndexEmails: string[];
};
