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

  const StatsCard({
    super.key,
    required this.currentStreak,
    required this.bestStreak,
    required this.totalNights,
  });

  @override
  Widget build(BuildContext context) {
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
      child: IntrinsicHeight(
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
