import 'package:flutter/material.dart';

import '../../data/models/achievement_model.dart';
import '../../theme/lumi_tokens.dart';

typedef AchievementDisplayGroup = ({
  AchievementCategory category,
  String label,
  IconData icon,
});

typedef EarnedAchievementDisplay = ({
  AchievementModel template,
  AchievementModel earned,
});

/// Display order + labels + icons for the badge groups (no emoji — unified
/// Material icons, coloured by category). Streak is deliberately omitted.
const achievementDisplayGroups = <AchievementDisplayGroup>[
  (
    category: AchievementCategory.readingDays,
    label: 'Reading Nights',
    icon: Icons.nightlight_round,
  ),
  (
    category: AchievementCategory.books,
    label: 'Books',
    icon: Icons.menu_book_rounded,
  ),
  (
    category: AchievementCategory.minutes,
    label: 'Reading Time',
    icon: Icons.schedule_rounded,
  ),
  (
    category: AchievementCategory.special,
    label: 'Special',
    icon: Icons.star_rounded,
  ),
];

// Warm accents not in the core token palette (gold/amber read as "reward/time").
const _amberAccent = Color(0xFFF59E0B);

/// Relevant, good-contrast colour per category — used for both the section
/// header icon and its badge icons.
Color achievementCategoryColor(AchievementCategory category) {
  switch (category) {
    case AchievementCategory.readingDays:
      return LumiTokens.blue;
    case AchievementCategory.books:
      return LumiTokens.green;
    case AchievementCategory.minutes:
      return _amberAccent;
    case AchievementCategory.special:
      return LumiTokens.red;
    default:
      return LumiTokens.muted;
  }
}

/// A unified Material icon per badge (by stable id, with a category fallback
/// for any custom/unknown achievement).
IconData achievementIconFor(AchievementModel achievement) {
  switch (achievement.id) {
    case 'days_t1':
      return Icons.bedtime_rounded;
    case 'days_t2':
      return Icons.nightlight_round;
    case 'days_t3':
      return Icons.dark_mode_rounded;
    case 'days_t4':
      return Icons.calendar_month_rounded;
    case 'books_t1':
      return Icons.menu_book_rounded;
    case 'books_t2':
      return Icons.auto_stories_rounded;
    case 'books_t3':
      return Icons.local_library_rounded;
    case 'books_t4':
      return Icons.library_books_rounded;
    case 'books_t5':
      return Icons.workspace_premium_rounded;
    case 'minutes_t1':
      return Icons.schedule_rounded;
    case 'minutes_t2':
      return Icons.update_rounded;
    case 'minutes_t3':
      return Icons.directions_run_rounded;
    case 'minutes_t4':
      return Icons.hourglass_bottom_rounded;
    case 'minutes_t5':
      return Icons.all_inclusive_rounded;
    case 'first_log':
      return Icons.flag_rounded;
  }
  switch (achievement.category) {
    case AchievementCategory.readingDays:
      return Icons.nightlight_round;
    case AchievementCategory.books:
      return Icons.menu_book_rounded;
    case AchievementCategory.minutes:
      return Icons.schedule_rounded;
    case AchievementCategory.special:
      return Icons.star_rounded;
    default:
      return Icons.emoji_events_rounded;
  }
}

/// Dedupe earned achievements by stable id. If a legacy write contains the
/// same id more than once, keep the newest earnedAt so previews do not show
/// repeated copies of the same badge.
Map<String, AchievementModel> earnedAchievementMap(
  Iterable<AchievementModel> achievements,
) {
  final byId = <String, AchievementModel>{};
  for (final achievement in achievements) {
    if (achievement.id.isEmpty) continue;
    final existing = byId[achievement.id];
    if (existing == null || achievement.earnedAt.isAfter(existing.earnedAt)) {
      byId[achievement.id] = achievement;
    }
  }
  return byId;
}

/// Canonical template set for achievement surfaces.
///
/// Streak badges are hidden because the reward engine no longer awards them.
/// Book badges are retired as goals, so they appear only when already earned
/// by legacy data.
List<AchievementModel> displayableAchievementTemplates({
  required Map<String, AchievementModel> earnedById,
  AchievementThresholds thresholds = AchievementThresholds.defaults,
  AchievementCustomization? customization,
}) {
  return AchievementTemplates.generateTemplates(
    thresholds,
    customization: customization ?? AchievementCustomization.empty,
  )
      .where((template) => template.category != AchievementCategory.streak)
      .where(
        (template) =>
            template.category != AchievementCategory.books ||
            earnedById.containsKey(template.id),
      )
      .toList();
}

List<EarnedAchievementDisplay> earnedAchievementDisplays({
  required Map<String, AchievementModel> earnedById,
  AchievementThresholds thresholds = AchievementThresholds.defaults,
  AchievementCustomization? customization,
}) {
  final templates = displayableAchievementTemplates(
    earnedById: earnedById,
    thresholds: thresholds,
    customization: customization,
  );
  final displays = <EarnedAchievementDisplay>[
    for (final template in templates)
      if (earnedById[template.id] != null)
        (template: template, earned: earnedById[template.id]!),
  ];
  displays.sort((a, b) => b.earned.earnedAt.compareTo(a.earned.earnedAt));
  return displays;
}
