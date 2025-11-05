import 'package:flutter/material.dart';
import '../../theme/minimal_theme.dart';
import 'rounded_card.dart';

/// Card with icon, title, and subtitle
class IconCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final VoidCallback? onTap;

  const IconCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor = MinimalTheme.primaryPurple,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return RoundedCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(MinimalTheme.radiusMedium),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 24,
            ),
          ),
          const SizedBox(width: MinimalTheme.spaceM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: MinimalTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 14,
                    color: MinimalTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: MinimalTheme.textSecondary,
          ),
        ],
      ),
    );
  }
}

/// Compact stat card with icon and value
class StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color iconColor;

  const StatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.iconColor = MinimalTheme.primaryPurple,
  });

  @override
  Widget build(BuildContext context) {
    return RoundedCard(
      padding: const EdgeInsets.all(MinimalTheme.spaceM),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 28,
            ),
          ),
          const SizedBox(height: MinimalTheme.spaceM),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: MinimalTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: MinimalTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Horizontal stat card
class HorizontalStatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color iconColor;

  const HorizontalStatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.iconColor = MinimalTheme.primaryPurple,
  });

  @override
  Widget build(BuildContext context) {
    return RoundedCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(MinimalTheme.radiusSmall),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 24,
            ),
          ),
          const SizedBox(width: MinimalTheme.spaceM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: MinimalTheme.textPrimary,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: MinimalTheme.textSecondary,
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
