import type { FirestoreTimestamp } from "./common";

export const GoalType = {
  dailyMinutes: "dailyMinutes",
  weeklyMinutes: "weeklyMinutes",
  monthlyMinutes: "monthlyMinutes",
  dailyStreak: "dailyStreak",
  booksToRead: "booksToRead",
  pagesPerDay: "pagesPerDay",
  custom: "custom",
} as const;
export type GoalType = (typeof GoalType)[keyof typeof GoalType];

export const GoalStatus = {
  active: "active",
  completed: "completed",
  failed: "failed",
  paused: "paused",
} as const;
export type GoalStatus = (typeof GoalStatus)[keyof typeof GoalStatus];

export interface ReadingGoal {
  id: string;
  studentId: string;
  schoolId: string;
  type: GoalType;
  title: string;
  description?: string;
  targetValue: number;
  currentValue: number;
  startDate: FirestoreTimestamp;
  endDate: FirestoreTimestamp;
  status: GoalStatus;
  completedAt?: FirestoreTimestamp;
  rewardMessage?: string;
  parentMessage?: string;
  createdAt: FirestoreTimestamp;
  metadata?: Record<string, unknown>;
}
