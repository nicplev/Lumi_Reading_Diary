import type { FirestoreTimestamp } from "./common";

export const OnboardingStatus = {
  demo: "demo",
  interested: "interested",
  registered: "registered",
  setupInProgress: "setupInProgress",
  active: "active",
  suspended: "suspended",
} as const;
export type OnboardingStatus =
  (typeof OnboardingStatus)[keyof typeof OnboardingStatus];

export const OnboardingStep = {
  schoolInfo: "schoolInfo",
  adminAccount: "adminAccount",
  readingLevels: "readingLevels",
  importData: "importData",
  inviteTeachers: "inviteTeachers",
  completed: "completed",
} as const;
export type OnboardingStep =
  (typeof OnboardingStep)[keyof typeof OnboardingStep];

export interface SchoolOnboarding {
  id: string;
  schoolName: string;
  contactEmail: string;
  contactPhone?: string;
  contactPerson?: string;
  status: OnboardingStatus;
  currentStep: OnboardingStep;
  completedSteps: OnboardingStep[];
  createdAt: FirestoreTimestamp;
  lastUpdatedAt?: FirestoreTimestamp;
  schoolId?: string;
  adminUserId?: string;
  metadata?: Record<string, unknown>;
  demoScheduledAt?: FirestoreTimestamp;
  registrationCompletedAt?: FirestoreTimestamp;
  referralSource?: string;
  estimatedStudentCount: number;
  estimatedTeacherCount: number;
}
