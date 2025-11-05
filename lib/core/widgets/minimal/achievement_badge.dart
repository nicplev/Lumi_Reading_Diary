import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/minimal_theme.dart';
import 'rounded_card.dart';

/// Achievement badge widget
class AchievementBadge extends StatelessWidget {
  final String title;
  final String description;
  final String emoji;
  final bool isEarned;
  final Color? color;
  final DateTime? earnedDate;
  final VoidCallback? onTap;

  const AchievementBadge({
    super.key,
    required this.title,
    required this.description,
    required this.emoji,
    this.isEarned = false,
    this.color,
    this.earnedDate,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedRoundedCard(
      onTap: onTap,
      padding: const EdgeInsets.all(MinimalTheme.spaceM),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Badge icon
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: isEarned
                  ? (color != null
                      ? LinearGradient(
                          colors: [color!, color!.withValues(alpha: 0.7)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : MinimalTheme.purpleGradient)
                  : null,
              color: isEarned
                  ? null
                  : MinimalTheme.textSecondary.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              boxShadow: isEarned ? MinimalTheme.softShadow() : null,
            ),
            child: Center(
              child: Text(
                emoji,
                style: TextStyle(
                  fontSize: 32,
                  color: isEarned ? null : MinimalTheme.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(height: MinimalTheme.spaceM),
          // Title
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isEarned
                  ? MinimalTheme.textPrimary
                  : MinimalTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          // Description
          Text(
            description,
            style: TextStyle(
              fontSize: 11,
              color: isEarned
                  ? MinimalTheme.textSecondary
                  : MinimalTheme.textSecondary.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (isEarned && earnedDate != null) ...[
            const SizedBox(height: 4),
            Text(
              DateFormat('MMM d, yyyy').format(earnedDate!),
              style: TextStyle(
                fontSize: 10,
                color: color ?? MinimalTheme.green,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Large achievement card for detail view
class AchievementCard extends StatelessWidget {
  final String title;
  final String description;
  final String emoji;
  final bool isEarned;
  final Color? color;
  final DateTime? earnedDate;
  final String? requirement;

  const AchievementCard({
    super.key,
    required this.title,
    required this.description,
    this.isEarned = false,
    this.emoji = '🏆',
    this.color,
    this.earnedDate,
    this.requirement,
  });

  @override
  Widget build(BuildContext context) {
    return RoundedCard(
      padding: const EdgeInsets.all(MinimalTheme.spaceXL),
      child: Column(
        children: [
          // Badge icon
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: isEarned
                  ? (color != null
                      ? LinearGradient(
                          colors: [color!, color!.withValues(alpha: 0.7)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : MinimalTheme.purpleGradient)
                  : null,
              color: isEarned
                  ? null
                  : MinimalTheme.textSecondary.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              boxShadow: isEarned ? MinimalTheme.softShadow() : null,
            ),
            child: Center(
              child: Text(
                emoji,
                style: const TextStyle(fontSize: 56),
              ),
            ),
          ),
          const SizedBox(height: MinimalTheme.spaceL),
          // Title
          Text(
            title,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: isEarned
                  ? MinimalTheme.textPrimary
                  : MinimalTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: MinimalTheme.spaceM),
          // Description
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: isEarned
                  ? MinimalTheme.textSecondary
                  : MinimalTheme.textSecondary.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
          if (isEarned && earnedDate != null) ...[
            const SizedBox(height: MinimalTheme.spaceL),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: MinimalTheme.spaceL,
                vertical: MinimalTheme.spaceM,
              ),
              decoration: BoxDecoration(
                color: (color ?? MinimalTheme.green).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(MinimalTheme.radiusPill),
              ),
              child: Text(
                'Earned ${DateFormat('MMMM d, yyyy').format(earnedDate!)}',
                style: TextStyle(
                  fontSize: 12,
                  color: color ?? MinimalTheme.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          if (!isEarned && requirement != null) ...[
            const SizedBox(height: MinimalTheme.spaceL),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: MinimalTheme.spaceL,
                vertical: MinimalTheme.spaceM,
              ),
              decoration: BoxDecoration(
                color: MinimalTheme.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(MinimalTheme.radiusPill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: MinimalTheme.orange,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    requirement!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: MinimalTheme.orange,
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
}
