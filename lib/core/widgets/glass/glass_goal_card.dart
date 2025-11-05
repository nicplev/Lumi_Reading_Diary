import 'package:flutter/material.dart';
import '../../theme/liquid_glass_theme.dart';
import '../../theme/app_colors.dart';
import 'glass_card.dart';
import 'glass_progress_bar.dart';

/// Track progress towards reading goals
class GlassGoalCard extends StatelessWidget {
  final String title;
  final String target;
  final int current;
  final int total;
  final String? message;
  final Gradient? gradient;
  final IconData? icon;

  const GlassGoalCard({
    super.key,
    required this.title,
    required this.target,
    required this.current,
    required this.total,
    this.message,
    this.gradient,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0;
    final percentage = (progress * 100).round();

    return GlassCard(
      padding: const EdgeInsets.all(LiquidGlassTheme.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  color: AppColors.primaryBlue,
                  size: 24,
                ),
                const SizedBox(width: LiquidGlassTheme.spacingSm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.darkGray,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Goal: $target',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.gray,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$percentage%',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: progress >= 1.0 ? AppColors.success : AppColors.primaryBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: LiquidGlassTheme.spacingMd),
          // Progress bar
          GlassProgressBar(
            progress: progress,
            gradient: gradient,
            height: 10,
          ),
          const SizedBox(height: LiquidGlassTheme.spacingSm),
          // Current/Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$current / $total',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkGray,
                ),
              ),
              if (message != null)
                Text(
                  message!,
                  style: TextStyle(
                    fontSize: 12,
                    color: progress >= 1.0 ? AppColors.success : AppColors.gray,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Daily reading goal widget with Lumi mascot
class GlassDailyGoalWidget extends StatelessWidget {
  final int minutesRead;
  final int goalMinutes;
  final VoidCallback? onContinue;

  const GlassDailyGoalWidget({
    super.key,
    required this.minutesRead,
    required this.goalMinutes,
    this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final progress = goalMinutes > 0 ? (minutesRead / goalMinutes).clamp(0.0, 1.0) : 0.0;
    final isComplete = progress >= 1.0;

    return GlassCard(
      padding: const EdgeInsets.all(LiquidGlassTheme.spacingLg),
      child: Column(
        children: [
          // Header with Lumi mascot emoji
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: isComplete
                      ? LiquidGlassTheme.successGradient
                      : LiquidGlassTheme.readingGradient,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    isComplete ? '🎉' : '📚',
                    style: const TextStyle(fontSize: 28),
                  ),
                ),
              ),
              const SizedBox(width: LiquidGlassTheme.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isComplete ? 'Goal Complete!' : 'Daily Reading Goal',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: isComplete ? AppColors.success : AppColors.darkGray,
                      ),
                    ),
                    Text(
                      '$minutesRead / $goalMinutes minutes',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.gray,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: LiquidGlassTheme.spacingLg),
          // Progress circle
          GlassProgressCircle(
            progress: progress,
            label: '$minutesRead',
            sublabel: 'minutes',
            size: 140,
            gradient: isComplete
                ? LiquidGlassTheme.successGradient
                : LiquidGlassTheme.readingGradient,
          ),
          if (!isComplete) ...[
            const SizedBox(height: LiquidGlassTheme.spacingLg),
            Text(
              '${goalMinutes - minutesRead} minutes to go!',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.gray,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (isComplete) ...[
            const SizedBox(height: LiquidGlassTheme.spacingMd),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: LiquidGlassTheme.spacingLg,
                vertical: LiquidGlassTheme.spacingSm,
              ),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(LiquidGlassTheme.radiusCapsule),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle,
                    color: AppColors.success,
                    size: 18,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Great job! Keep it up!',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.success,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
