// ─── Achievement system: constants & pure evaluation ─────────────────────────
//
// Dependency-free on purpose so the awarding logic can be unit-tested
// (see test/achievements.test.js). index.ts imports these; the Firestore-backed
// threshold loader (resolveAchievementThresholds) and the
// detectAchievements / backfillAchievements wiring stay in index.ts.

// Keep in sync with AchievementThresholds.defaults in
// lib/data/models/achievement_model.dart. readingDays is the primary
// (cumulative "nights read") reward ladder; streak tiers and books tiers are
// no longer awarded (books kept here only for legacy threshold configs).
export const DEFAULT_ACHIEVEMENT_THRESHOLDS = {
  streak: [5, 10, 20, 50, 100],
  books: [5, 10, 25, 50, 100],
  minutes: [300, 600, 1500, 3000, 6000],
  readingDays: [10, 50, 100, 365],
};

export interface AchievementTierMeta {
  id: string;
  name: string;
  icon: string;
  category: string;
  rarity: string;
  requirementType: string;
  description: (value: number) => string;
}

// NOTE: streak tiers are intentionally NOT awarded. Streaks are a gentle,
// secondary signal that earns no rewards — cumulative "nights read" (DAYS_TIERS)
// is the reward ladder, so a missed night never costs a child a badge. Streak
// badges earned under the old system remain on student docs and still render.

// NOTE: books tiers are intentionally NOT awarded either. "Books read" cannot
// be tracked honestly — totalBooksRead counts bookTitles per log (a novel read
// across 10 nights scores 10; free-text titles dedupe nothing), so a books
// ladder rewards re-logging, not reading. Rewards key on minutes and
// cumulative nights instead. Books badges earned under the old system remain
// on student docs and still render; the tier metadata stays for that.

/* eslint-disable max-len */
export const BOOKS_TIERS: AchievementTierMeta[] = [
  {id: "books_t1", name: "Book Beginner", icon: "📖", category: "books", rarity: "common", requirementType: "books", description: (v) => `Read ${v} books!`},
  {id: "books_t2", name: "Book Collector", icon: "📚", category: "books", rarity: "uncommon", requirementType: "books", description: (v) => `Read ${v} books!`},
  {id: "books_t3", name: "Avid Reader", icon: "📗", category: "books", rarity: "rare", requirementType: "books", description: (v) => `Read ${v} books!`},
  {id: "books_t4", name: "Bookworm", icon: "🐛", category: "books", rarity: "epic", requirementType: "books", description: (v) => `Read ${v} books!`},
  {id: "books_t5", name: "Reading Legend", icon: "🏆", category: "books", rarity: "legendary", requirementType: "books", description: (v) => `Read ${v} books!`},
];

export const MINUTES_TIERS: AchievementTierMeta[] = [
  {id: "minutes_t1", name: "Hour Hand", icon: "⏰", category: "minutes", rarity: "common", requirementType: "minutes", description: (v) => `Read for ${v / 60} hours total!`},
  {id: "minutes_t2", name: "Time Traveler", icon: "⌚", category: "minutes", rarity: "uncommon", requirementType: "minutes", description: (v) => `Read for ${v / 60} hours total!`},
  {id: "minutes_t3", name: "Marathon Reader", icon: "🏃", category: "minutes", rarity: "rare", requirementType: "minutes", description: (v) => `Read for ${v / 60} hours total!`},
  {id: "minutes_t4", name: "Time Master", icon: "⏳", category: "minutes", rarity: "epic", requirementType: "minutes", description: (v) => `Read for ${v / 60} hours total!`},
  {id: "minutes_t5", name: "Eternal Reader", icon: "♾️", category: "minutes", rarity: "legendary", requirementType: "minutes", description: (v) => `Read for ${v / 60} hours total!`},
];

// Cumulative "nights read" ladder — the primary reward track. Every night
// counts forever and is never lost. Thresholds: see DEFAULT_ACHIEVEMENT_THRESHOLDS
// (readingDays) and the mirror in achievement_model.dart.
export const DAYS_TIERS: AchievementTierMeta[] = [
  {id: "days_t1", name: "Decade Reader", icon: "📅", category: "readingDays", rarity: "common", requirementType: "days", description: (v) => `Read on ${v} nights!`},
  {id: "days_t2", name: "Fifty Nights", icon: "🌙", category: "readingDays", rarity: "rare", requirementType: "days", description: (v) => `Read on ${v} nights!`},
  {id: "days_t3", name: "Century Reader", icon: "💯", category: "readingDays", rarity: "epic", requirementType: "days", description: (v) => `Read on ${v} nights!`},
  {id: "days_t4", name: "Year of Reading", icon: "🏆", category: "readingDays", rarity: "legendary", requirementType: "days", description: (v) => `Read on ${v} nights — a whole year!`},
];
/* eslint-enable max-len */

export const FIRST_LOG_ACHIEVEMENT = {
  id: "first_log",
  name: "First Chapter",
  description: "Logged your very first reading session!",
  icon: "📖",
  category: "special",
  rarity: "common",
  requirementType: "days",
  requiredValue: 1,
};

export type AchievementThresholdSet = {
  streak: number[]; books: number[]; minutes: number[]; readingDays: number[];
};

export type AwardableAchievement = {
  id: string; name: string; description: string; icon: string;
  category: string; rarity: string; requirementType: string; requiredValue: number;
};

/**
 * Current-state (idempotent) achievement evaluation: returns every tier the
 * student now qualifies for that isn't already earned.
 *
 * This is deliberately NOT a "threshold crossing" check. Awarding on current
 * state (guarded by `earnedIds` + `arrayUnion` at the write site) self-heals
 * for any student whose stats reached a threshold outside a clean incremental
 * update — seed / imported data, a stats recompute, or the detector being
 * deployed after the fact. Crossing-only logic left those students permanently
 * un-awarded.
 * @param {Record<string, unknown>} stats The student's aggregated stats.
 * @param {Set<string>} earnedIds Ids of achievements already earned.
 * @param {AchievementThresholdSet} thresholds Resolved per-category thresholds.
 * @return {AwardableAchievement[]} Achievements the student now qualifies for.
 */
export function computeAwardableAchievements(
  stats: Record<string, unknown>,
  earnedIds: Set<string>,
  thresholds: AchievementThresholdSet,
): AwardableAchievement[] {
  const toAward: AwardableAchievement[] = [];
  const num = (v: unknown): number =>
    typeof v === "number" && isFinite(v) ? v : 0;

  const checkTiers = (
    tiers: AchievementTierMeta[],
    tierThresholds: number[],
    currentVal: number,
  ) => {
    for (let i = 0; i < tiers.length; i++) {
      const threshold = tierThresholds[i];
      if (threshold === undefined) continue;
      if (earnedIds.has(tiers[i].id)) continue;
      if (currentVal >= threshold) {
        toAward.push({
          ...tiers[i],
          description: tiers[i].description(threshold),
          requiredValue: threshold,
        });
      }
    }
  };

  // Streaks and books deliberately award nothing (see the notes above the
  // tier tables) — minutes and cumulative nights are the reward ladders.
  checkTiers(MINUTES_TIERS, thresholds.minutes, num(stats.totalMinutesRead));
  checkTiers(DAYS_TIERS, thresholds.readingDays, num(stats.totalReadingDays));

  // First-log special achievement.
  if (
    !earnedIds.has(FIRST_LOG_ACHIEVEMENT.id) &&
    num(stats.totalReadingDays) >= 1
  ) {
    toAward.push({...FIRST_LOG_ACHIEVEMENT});
  }
  return toAward;
}
