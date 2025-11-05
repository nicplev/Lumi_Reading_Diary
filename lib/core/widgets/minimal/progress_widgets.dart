import 'package:flutter/material.dart';
import '../../theme/minimal_theme.dart';

/// Circular progress indicator with label
class CircularProgress extends StatelessWidget {
  final double progress;
  final String label;
  final String? sublabel;
  final double size;
  final Color? color;

  const CircularProgress({
    super.key,
    required this.progress,
    required this.label,
    this.sublabel,
    this.size = 120,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final progressColor = color ?? MinimalTheme.primaryPurple;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: size * 0.08,
              backgroundColor: MinimalTheme.lightPurple.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: size * 0.25,
                  fontWeight: FontWeight.bold,
                  color: MinimalTheme.textPrimary,
                ),
              ),
              if (sublabel != null)
                Text(
                  sublabel!,
                  style: TextStyle(
                    fontSize: size * 0.12,
                    color: MinimalTheme.textSecondary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Linear progress bar with label
class LinearProgressBar extends StatelessWidget {
  final double progress;
  final String? label;
  final Color? color;
  final double height;

  const LinearProgressBar({
    super.key,
    required this.progress,
    this.label,
    this.color,
    this.height = 8,
  });

  @override
  Widget build(BuildContext context) {
    final progressColor = color ?? MinimalTheme.primaryPurple;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: MinimalTheme.textPrimary,
                ),
              ),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: progressColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: MinimalTheme.spaceS),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: height,
            backgroundColor: MinimalTheme.lightPurple.withValues(alpha: 0.3),
            valueColor: AlwaysStoppedAnimation<Color>(progressColor),
          ),
        ),
      ],
    );
  }
}

/// Progress card with circular indicator
class ProgressCard extends StatelessWidget {
  final String title;
  final double progress;
  final String currentValue;
  final String targetValue;
  final IconData? icon;
  final Color? color;

  const ProgressCard({
    super.key,
    required this.title,
    required this.progress,
    required this.currentValue,
    required this.targetValue,
    this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final progressColor = color ?? MinimalTheme.primaryPurple;

    return Container(
      padding: const EdgeInsets.all(MinimalTheme.spaceL),
      decoration: BoxDecoration(
        color: MinimalTheme.white,
        borderRadius: BorderRadius.circular(MinimalTheme.radiusLarge),
        boxShadow: MinimalTheme.cardShadow(),
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: progressColor, size: 24),
                const SizedBox(width: MinimalTheme.spaceM),
              ],
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: MinimalTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: MinimalTheme.spaceL),
          CircularProgress(
            progress: progress,
            label: currentValue,
            sublabel: 'of $targetValue',
            color: progressColor,
          ),
          const SizedBox(height: MinimalTheme.spaceM),
          LinearProgressBar(
            progress: progress,
            color: progressColor,
            height: 6,
          ),
        ],
      ),
    );
  }
}
