import 'package:flutter/material.dart';
import '../../theme/liquid_glass_theme.dart';
import '../../theme/app_colors.dart';
import 'glass_card.dart';

/// Achievement badge widget
class GlassAchievementBadge extends StatelessWidget {
  final String title;
  final String description;
  final String emoji;
  final bool isEarned;
  final Gradient? gradient;
  final DateTime? earnedDate;
  final VoidCallback? onTap;

  const GlassAchievementBadge({
    super.key,
    required this.title,
    required this.description,
    required this.emoji,
    this.isEarned = false,
    this.gradient,
    this.earnedDate,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedGlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(LiquidGlassTheme.spacingMd),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Badge icon
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: isEarned
                  ? (gradient ?? LiquidGlassTheme.successGradient)
                  : null,
              color: isEarned ? null : AppColors.gray.withOpacity(0.2),
              shape: BoxShape.circle,
              boxShadow: isEarned
                  ? LiquidGlassTheme.glowShadow(
                      color: AppColors.primaryBlue,
                    )
                  : null,
            ),
            child: Center(
              child: Text(
                emoji,
                style: TextStyle(
                  fontSize: 32,
                  color: isEarned ? null : AppColors.gray,
                ),
              ),
            ),
          ),
          const SizedBox(height: LiquidGlassTheme.spacingSm),
          // Title
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isEarned ? AppColors.darkGray : AppColors.gray,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          // Description
          Text(
            description,
            style: TextStyle(
              fontSize: 11,
              color: isEarned ? AppColors.gray : AppColors.gray.withOpacity(0.6),
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (isEarned && earnedDate != null) ...[
            const SizedBox(height: 4),
            Text(
              _formatDate(earnedDate!),
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

/// Large achievement card for detail view
class GlassAchievementCard extends StatelessWidget {
  final String title;
  final String description;
  final String emoji;
  final bool isEarned;
  final Gradient? gradient;
  final DateTime? earnedDate;
  final String? requirement;

  const GlassAchievementCard({
    super.key,
    required this.title,
    required this.description,
    required this.emoji,
    this.isEarned = false,
    this.gradient,
    this.earnedDate,
    this.requirement,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(LiquidGlassTheme.spacingLg),
      child: Column(
        children: [
          // Badge icon
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: isEarned
                  ? (gradient ?? LiquidGlassTheme.successGradient)
                  : null,
              color: isEarned ? null : AppColors.gray.withOpacity(0.2),
              shape: BoxShape.circle,
              boxShadow: isEarned
                  ? LiquidGlassTheme.glowShadow(
                      color: AppColors.primaryBlue,
                      blurRadius: 30,
                    )
                  : null,
            ),
            child: Center(
              child: Text(
                emoji,
                style: const TextStyle(fontSize: 56),
              ),
            ),
          ),
          const SizedBox(height: LiquidGlassTheme.spacingMd),
          // Title
          Text(
            title,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: isEarned ? AppColors.darkGray : AppColors.gray,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: LiquidGlassTheme.spacingSm),
          // Description
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: isEarned ? AppColors.gray : AppColors.gray.withOpacity(0.6),
            ),
            textAlign: TextAlign.center,
          ),
          if (isEarned && earnedDate != null) ...[
            const SizedBox(height: LiquidGlassTheme.spacingMd),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: LiquidGlassTheme.spacingMd,
                vertical: LiquidGlassTheme.spacingSm,
              ),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(LiquidGlassTheme.radiusCapsule),
              ),
              child: Text(
                'Earned ${_formatDate(earnedDate!)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          if (!isEarned && requirement != null) ...[
            const SizedBox(height: LiquidGlassTheme.spacingMd),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: LiquidGlassTheme.spacingMd,
                vertical: LiquidGlassTheme.spacingSm,
              ),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(LiquidGlassTheme.radiusCapsule),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    requirement!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.warning,
                      fontWeight: FontWeight.w600,
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

  String _formatDate(DateTime date) {
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
