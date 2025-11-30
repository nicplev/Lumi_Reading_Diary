import 'package:flutter/material.dart';
import 'package:lumi_reading_tracker/data/models/achievement_model.dart';
import 'package:lumi_reading_tracker/core/theme/app_colors.dart';
import 'package:lumi_reading_tracker/core/theme/lumi_text_styles.dart';
import 'package:lumi_reading_tracker/core/theme/lumi_spacing.dart';
import 'package:lumi_reading_tracker/core/theme/lumi_borders.dart';
import 'package:lumi_reading_tracker/core/widgets/lumi/lumi_buttons.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Celebration popup shown when an achievement is unlocked
class AchievementUnlockPopup extends StatelessWidget {
  final AchievementModel achievement;

  const AchievementUnlockPopup({
    super.key,
    required this.achievement,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: LumiPadding.allL,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(achievement.rarity.color).withValues(alpha: 0.3),
              AppColors.white,
              Color(achievement.rarity.color).withValues(alpha: 0.2),
            ],
          ),
          borderRadius: LumiBorders.large,
          border: Border.all(
            color: Color(achievement.rarity.color),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Color(achievement.rarity.color).withValues(alpha: 0.3),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // "Achievement Unlocked!" header
            Text(
              'Achievement Unlocked!',
              style: LumiTextStyles.h2(
                color: Color(achievement.rarity.color),
              ),
              textAlign: TextAlign.center,
            )
                .animate(onPlay: (controller) => controller.repeat())
                .shimmer(duration: 2000.ms),

            LumiGap.m,

            // Large animated icon with glow effect
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(achievement.rarity.color).withValues(alpha: 0.2),
                    Colors.transparent,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(achievement.rarity.color).withValues(alpha: 0.5),
                    blurRadius: 30,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  achievement.icon,
                  style: const TextStyle(fontSize: 72),
                ),
              ),
            )
                .animate(onPlay: (controller) => controller.repeat())
                .shimmer(duration: 2000.ms)
                .shake(hz: 2, rotation: 0.05),

            LumiGap.m,

            // Achievement name
            Text(
              achievement.name,
              style: LumiTextStyles.h3(
                color: AppColors.charcoal,
              ),
              textAlign: TextAlign.center,
            ),

            LumiGap.xs,

            // Achievement description
            Text(
              achievement.description,
              style: LumiTextStyles.body(
                color: AppColors.charcoal.withValues(alpha: 0.8),
              ),
              textAlign: TextAlign.center,
            ),

            LumiGap.s,

            // Rarity badge
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: LumiSpacing.s,
                vertical: LumiSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: Color(achievement.rarity.color),
                borderRadius: LumiBorders.medium,
              ),
              child: Text(
                achievement.rarity.displayName.toUpperCase(),
                style: LumiTextStyles.label(
                  color: AppColors.white,
                ).copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),

            LumiGap.l,

            // Dismiss button
            SizedBox(
              width: double.infinity,
              child: LumiPrimaryButton(
                onPressed: () => Navigator.pop(context),
                text: 'Awesome!',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
