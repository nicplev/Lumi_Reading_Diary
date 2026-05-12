import type { FirestoreTimestamp } from "./common";

export const AchievementCategory = {
  streak: "streak",
  books: "books",
  minutes: "minutes",
  readingDays: "readingDays",
  levelProgress: "levelProgress",
  genre: "genre",
  special: "special",
  general: "general",
} as const;
export type AchievementCategory =
  (typeof AchievementCategory)[keyof typeof AchievementCategory];

export const AchievementRarity = {
  common: "common",
  uncommon: "uncommon",
  rare: "rare",
  epic: "epic",
  legendary: "legendary",
} as const;
export type AchievementRarity =
  (typeof AchievementRarity)[keyof typeof AchievementRarity];

export interface Achievement {
  id: string;
  name: string;
  description: string;
  icon: string;
  category: AchievementCategory;
  rarity: AchievementRarity;
  requiredValue: number;
  requirementType: string;
  earnedAt: FirestoreTimestamp;
  displayed: boolean;
  metadata?: Record<string, unknown>;
}
