import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/lumi_text_styles.dart';
import '../../theme/lumi_spacing.dart';

/// Lumi Design System - Stats Card
///
/// 3-column layout with vertical dividers showing key reading stats.
/// Each stat: icon (28px), number (24px bold), label (12px secondary).
class StatsCard extends StatelessWidget {
  final int currentStreak;
  final int bestStreak;
  final int totalNights;

  /// Streak freezes the student has banked (Rec 6). When > 0 a small
  /// footer reassures the parent that a missed day is protected.
  final int? streakFreezes;

  const StatsCard({
    super.key,
    required this.currentStreak,
    required this.bestStreak,
    required this.totalNights,
    this.streakFreezes,
  });

  @override
  Widget build(BuildContext context) {
    final freezes = streakFreezes ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.charcoal.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _StatColumn(
                icon: Icons.local_fire_department,
                iconColor: AppColors.warmOrange,
                value: currentStreak.toString(),
                label: 'Current\nStreak',
              ),
            ),
            Container(
              width: 1,
              color: AppColors.divider,
            ),
            Expanded(
              child: _StatColumn(
                icon: Icons.emoji_events,
                iconColor: AppColors.gold,
                value: bestStreak.toString(),
                label: 'Best\nStreak',
              ),
            ),
            Container(
              width: 1,
              color: AppColors.divider,
            ),
            Expanded(
              child: _StatColumn(
                icon: Icons.menu_book,
                iconColor: AppColors.rosePink,
                value: totalNights.toString(),
                label: 'Total\nNights',
              ),
            ),
          ],
        ),
          ),
          if (freezes > 0) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                vertical: 8,
                horizontal: 12,
              ),
              decoration: BoxDecoration(
                color: AppColors.skyBlue.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '❄️ $freezes streak ${freezes == 1 ? 'freeze' : 'freezes'} '
                'banked — a missed day is covered',
                style: LumiTextStyles.caption(color: AppColors.charcoal),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _StatColumn({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 28),
        const SizedBox(height: LumiSpacing.xs),
        Text(
          value,
          style: LumiTextStyles.h2(color: AppColors.charcoal),
        ),
        const SizedBox(height: LumiSpacing.xxs),
        Text(
          label,
          style: LumiTextStyles.caption(),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
