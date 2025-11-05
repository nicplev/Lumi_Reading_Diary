import 'package:flutter/material.dart';
import '../../theme/liquid_glass_theme.dart';
import '../../theme/app_colors.dart';
import 'glass_card.dart';

/// Display single statistic with gradient text
class GlassStatCard extends StatelessWidget {
  final String value;
  final String label;
  final Gradient? gradient;
  final IconData? icon;
  final Color? iconColor;

  const GlassStatCard({
    super.key,
    required this.value,
    required this.label,
    this.gradient,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(LiquidGlassTheme.spacingLg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 32,
              color: iconColor ?? AppColors.primaryBlue,
            ),
            const SizedBox(height: LiquidGlassTheme.spacingSm),
          ],
          gradient != null
              ? ShaderMask(
                  shaderCallback: (bounds) => gradient!.createShader(bounds),
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                )
              : Text(
                  value,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: AppColors.darkGray,
                  ),
                ),
          const SizedBox(height: LiquidGlassTheme.spacingXs),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.gray,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Streak card with fire icon
class GlassStreakCard extends StatelessWidget {
  final int days;
  final String? subtitle;

  const GlassStreakCard({
    super.key,
    required this.days,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(LiquidGlassTheme.spacingLg),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              gradient: LiquidGlassTheme.warmGradient,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text(
                '🔥',
                style: TextStyle(fontSize: 32),
              ),
            ),
          ),
          const SizedBox(width: LiquidGlassTheme.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) =>
                      LiquidGlassTheme.warmGradient.createShader(bounds),
                  child: Text(
                    '$days Day Streak!',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.gray,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Mini stat display for dashboard
class GlassMiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const GlassMiniStat({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(LiquidGlassTheme.spacingMd),
      child: Row(
        children: [
          Icon(
            icon,
            color: color ?? AppColors.primaryBlue,
            size: 24,
          ),
          const SizedBox(width: LiquidGlassTheme.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: color ?? AppColors.darkGray,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.gray,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
