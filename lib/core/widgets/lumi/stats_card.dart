import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/lumi_text_styles.dart';
import '../../theme/lumi_spacing.dart';

/// Lumi Design System - Stats Card
///
/// 3-column layout with vertical dividers. Total Nights (cumulative, the hero
/// metric) is foregrounded; the streaks are gentle secondary signals.
class StatsCard extends StatelessWidget {
  final int currentStreak;
  final int bestStreak;
  final int totalNights;

  /// Rest days remaining in the current streak (0–2). When exactly one has been
  /// used, a small footer reassures the parent the streak is still protected.
  final int? restDaysRemaining;

  const StatsCard({
    super.key,
    required this.currentStreak,
    required this.bestStreak,
    required this.totalNights,
    this.restDaysRemaining,
  });

  @override
  Widget build(BuildContext context) {
    final restDays = restDaysRemaining ?? 2;
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
                // Hero: cumulative nights read — the number that only ever grows.
                Expanded(
                  child: _StatColumn(
                    icon: Icons.menu_book,
                    iconColor: AppColors.rosePink,
                    value: totalNights.toString(),
                    label: 'Total\nNights',
                    prominent: true,
                  ),
                ),
                Container(width: 1, color: AppColors.divider),
                Expanded(
                  child: _StatColumn(
                    icon: Icons.local_fire_department,
                    iconColor: AppColors.warmOrange,
                    value: currentStreak.toString(),
                    label: 'Streak',
                  ),
                ),
                Container(width: 1, color: AppColors.divider),
                Expanded(
                  child: _StatColumn(
                    icon: Icons.emoji_events,
                    iconColor: AppColors.gold,
                    value: bestStreak.toString(),
                    label: 'Best\nStreak',
                  ),
                ),
              ],
            ),
          ),
          if (currentStreak > 0 && restDays == 1) ...[
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
                '🌙 1 rest day left — your streak is safe',
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

  /// When true the value is rendered larger to foreground the hero metric.
  final bool prominent;

  const _StatColumn({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    this.prominent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: prominent ? 32 : 26),
        const SizedBox(height: LumiSpacing.xs),
        Text(
          value,
          style: prominent
              ? LumiTextStyles.display(color: AppColors.charcoal)
                  .copyWith(fontSize: 30)
              : LumiTextStyles.h2(
                  color: AppColors.charcoal.withValues(alpha: 0.85),
                ),
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
