import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/teacher_constants.dart';
import '../../../../data/models/achievement_model.dart';
import '../models/student_achievement.dart';

/// Highlights the most recent achievements earned across the class.
class DashboardAchievementSpotlightCard extends StatelessWidget {
  final List<StudentAchievement> recentAchievements;

  const DashboardAchievementSpotlightCard({
    super.key,
    required this.recentAchievements,
  });

  @override
  Widget build(BuildContext context) {
    final top = recentAchievements.take(5).toList();

    // Count achievements earned in the last 7 days
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final thisWeekCount = recentAchievements
        .where((a) => a.achievement.earnedAt.isAfter(weekAgo))
        .length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
        border: Border.all(color: AppColors.teacherBorder),
        boxShadow: [
          BoxShadow(
            color: AppColors.charcoal.withValues(alpha: 0.04),
            blurRadius: 16,
            spreadRadius: -4,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text('Achievement Spotlight',
                  style: TeacherTypography.sectionHeader
                      .copyWith(color: AppColors.teacherPrimary)),
              const Spacer(),
              if (thisWeekCount > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.teacherPrimary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$thisWeekCount this week',
                    style: TeacherTypography.caption.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.teacherPrimary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          if (top.isEmpty)
            _buildEmptyState()
          else
            ...top.map((sa) => _buildRow(sa)),
        ],
      ),
    );
  }

  Widget _buildRow(StudentAchievement sa) {
    final a = sa.achievement;
    final rarityColor = Color(a.effectiveColor);
    final timeLabel = _relativeTime(a.earnedAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          // Emoji icon in coloured circle
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: rarityColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                a.icon,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Name + student
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.name,
                  style: TeacherTypography.bodyMedium
                      .copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${sa.studentFirstName} · $timeLabel',
                  style: TeacherTypography.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Rarity badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: rarityColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              a.rarity.displayName,
              style: TeacherTypography.caption.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: rarityColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _relativeTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(date).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dt.weekday - 1];
    }
    return '${dt.day}/${dt.month}';
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.military_tech_rounded,
                size: 32,
                color: AppColors.textSecondary.withValues(alpha: 0.3)),
            const SizedBox(height: 8),
            Text(
              "No achievements earned yet — they'll appear here!",
              style: TeacherTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
