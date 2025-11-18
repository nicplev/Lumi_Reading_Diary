import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lumi_reading_tracker/data/models/achievement_model.dart';
import 'package:intl/intl.dart';

/// Glass-styled achievement card
class GlassAchievementCard extends StatelessWidget {
  final AchievementModel achievement;
  final bool showDate;
  final VoidCallback? onTap;
  final bool animate;

  const GlassAchievementCard({
    super.key,
    required this.achievement,
    this.showDate = true,
    this.onTap,
    this.animate = false,
  });

  @override
  Widget build(BuildContext context) {
    final rarityColor = Color(achievement.rarity.color);

    Widget card = Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            rarityColor.withOpacity(0.2),
            rarityColor.withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: rarityColor.withOpacity(0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: rarityColor.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Achievement icon
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        rarityColor.withOpacity(0.3),
                        rarityColor.withOpacity(0.1),
                      ],
                    ),
                    border: Border.all(
                      color: rarityColor.withOpacity(0.5),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      achievement.icon,
                      style: const TextStyle(fontSize: 36),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Achievement details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name
                      Text(
                        achievement.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: rarityColor,
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Description
                      Text(
                        achievement.description,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),

                      if (showDate) ...[
                        const SizedBox(height: 8),

                        // Earned date
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 14,
                              color: Colors.white.withOpacity(0.6),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Earned ${DateFormat('MMM d, yyyy').format(achievement.earnedAt)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                // Rarity badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: rarityColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: rarityColor.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    achievement.rarity.displayName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: rarityColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Add animation if requested
    if (animate) {
      card = card
          .animate()
          .fadeIn(duration: 300.ms)
          .slideX(begin: 0.2, end: 0, duration: 300.ms)
          .then(delay: 100.ms)
          .shimmer(duration: 1000.ms, color: rarityColor.withOpacity(0.3));
    }

    return card;
  }
}

/// Compact achievement badge (for grids)
class GlassAchievementBadge extends StatelessWidget {
  final AchievementModel achievement;
  final VoidCallback? onTap;
  final bool locked;

  const GlassAchievementBadge({
    super.key,
    required this.achievement,
    this.onTap,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final rarityColor = Color(achievement.rarity.color);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: locked
              ? LinearGradient(
                  colors: [
                    Colors.grey.withOpacity(0.3),
                    Colors.grey.withOpacity(0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : LinearGradient(
                  colors: [
                    rarityColor.withOpacity(0.2),
                    rarityColor.withOpacity(0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: locked
                ? Colors.grey.withOpacity(0.3)
                : rarityColor.withOpacity(0.3),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: locked
                    ? null
                    : RadialGradient(
                        colors: [
                          rarityColor.withOpacity(0.3),
                          rarityColor.withOpacity(0.1),
                        ],
                      ),
                color: locked ? Colors.grey.withOpacity(0.2) : null,
              ),
              child: Center(
                child: locked
                    ? Icon(
                        Icons.lock,
                        size: 32,
                        color: Colors.grey.withOpacity(0.5),
                      )
                    : Text(
                        achievement.icon,
                        style: const TextStyle(fontSize: 32),
                      ),
              ),
            ),
            const SizedBox(height: 8),

            // Name
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                achievement.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: locked
                      ? Colors.grey.withOpacity(0.5)
                      : rarityColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Achievement unlock popup (celebration)
class AchievementUnlockPopup extends StatelessWidget {
  final AchievementModel achievement;
  final VoidCallback? onDismiss;

  const AchievementUnlockPopup({
    super.key,
    required this.achievement,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final rarityColor = Color(achievement.rarity.color);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              rarityColor.withOpacity(0.3),
              rarityColor.withOpacity(0.1),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: rarityColor.withOpacity(0.5),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: rarityColor.withOpacity(0.5),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Achievement Unlocked title
            Text(
              '🎉 Achievement Unlocked! 🎉',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: rarityColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Achievement icon with glow
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    rarityColor.withOpacity(0.4),
                    rarityColor.withOpacity(0.1),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: rarityColor.withOpacity(0.6),
                    blurRadius: 40,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  achievement.icon,
                  style: const TextStyle(fontSize: 64),
                ),
              ),
            )
                .animate(onPlay: (controller) => controller.repeat())
                .shimmer(duration: 2000.ms, color: rarityColor.withOpacity(0.5))
                .shake(duration: 1000.ms, hz: 2, rotation: 0.05),

            const SizedBox(height: 24),

            // Achievement name
            Text(
              achievement.name,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: rarityColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            // Rarity badge
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: rarityColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: rarityColor.withOpacity(0.5),
                  width: 1,
                ),
              ),
              child: Text(
                achievement.rarity.displayName.toUpperCase(),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: rarityColor,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Description
            Text(
              achievement.description,
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withOpacity(0.9),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Dismiss button
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                onDismiss?.call();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: rarityColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Awesome!',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).scale(
          begin: const Offset(0.8, 0.8),
          end: const Offset(1.0, 1.0),
          duration: 300.ms,
        );
  }

  /// Show the popup
  static Future<void> show(
    BuildContext context,
    AchievementModel achievement,
  ) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AchievementUnlockPopup(
        achievement: achievement,
      ),
    );
  }
}
