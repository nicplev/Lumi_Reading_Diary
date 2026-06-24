export type { FirestoreTimestamp } from "./common";

export { ReadingLevelSchema } from "./school";
export type { School, SchoolAccess, SchoolAccessStatus } from "./school";

export {
  ACTIVE_SUBSCRIPTION_STATUSES,
  isActiveSubscriptionStatus,
  SUBSCRIPTION_TIERS,
  tierForStudentCount,
} from "./school-subscription";
export type {
  SchoolSubscription,
  SubscriptionStatus,
  SubscriptionTier,
  SubscriptionTierBand,
  AcademicYearConfig,
} from "./school-subscription";

export { UserRole } from "./school-user";
export type { SchoolUser } from "./school-user";

export type { Parent } from "./parent";

export type {
  Student,
  StudentStats,
  ReadingLevelHistory,
  EnrollmentStatus,
  StudentAccess,
  StudentAccessStatus,
  StudentAccessSource,
} from "./student";

export type { Class } from "./class";

export { AllocationType, AllocationCadence } from "./allocation";
export type {
  Allocation,
  AllocationBookItem,
  StudentAllocationOverride,
} from "./allocation";

export type { Book } from "./book";

export { LogStatus, ReadingFeeling } from "./reading-log";
export type { ReadingLog } from "./reading-log";

export { GoalType, GoalStatus } from "./reading-goal";
export type { ReadingGoal } from "./reading-goal";

export type { ReadingGroup } from "./reading-group";

export type { ReadingLevelEvent } from "./reading-level-event";

export { OnboardingStatus, OnboardingStep } from "./school-onboarding";
export type { SchoolOnboarding } from "./school-onboarding";

export { LinkCodeStatus } from "./student-link-code";
export type { StudentLinkCode } from "./student-link-code";

export type { SchoolCode } from "./school-code";

export type { Notification } from "./notification";

export type { UserSchoolIndex } from "./user-school-index";

export { AchievementCategory, AchievementRarity } from "./achievement";
export type { Achievement } from "./achievement";
