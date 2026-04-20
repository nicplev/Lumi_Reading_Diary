import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_colors.dart';

/// Named variants of the Lumi flame mascot. Each value maps to one PNG in
/// `assets/lumi/`. Add a new value + asset path here when a new mascot
/// illustration is delivered.
enum LumiVariant {
  login,
  parent,
  parentWhy,
  teacher,
  teacherWhy,
  school,
  welcome,
  linking,
  forgot,
  promo,
  splash;

  String get asset => switch (this) {
    LumiVariant.login => 'assets/lumi/Lumi_Login.png',
    LumiVariant.parent => 'assets/lumi/Lumi_Parent.png',
    LumiVariant.parentWhy => 'assets/lumi/Lumi_Parent_Why.png',
    LumiVariant.teacher => 'assets/lumi/Lumi_Teacher.png',
    LumiVariant.teacherWhy => 'assets/lumi/Lumi_Teacher_Why.png',
    LumiVariant.school => 'assets/lumi/Lumi_School.png',
    LumiVariant.welcome => 'assets/lumi/Lumi_Welcome.png',
    LumiVariant.linking => 'assets/lumi/Lumi_Linking.png',
    LumiVariant.forgot => 'assets/lumi/Lumi_forgot.png',
    LumiVariant.promo => 'assets/lumi/Lumi_Promo.png',
    LumiVariant.splash => 'assets/lumi/Lumi_Splash_Screem.png',
  };
}

class LumiMascot extends StatelessWidget {
  final LumiVariant variant;
  final double size;
  final String? message;
  final bool animate;

  const LumiMascot({
    super.key,
    this.variant = LumiVariant.welcome,
    this.size = 120,
    this.message,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget mascot = SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        variant.asset,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.local_fire_department_rounded,
          size: size * 0.8,
          color: AppColors.lumiBody,
        ),
      ),
    );

    if (animate) {
      mascot = mascot
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .scaleXY(
            begin: 1.0,
            end: 1.04,
            duration: 2.seconds,
            curve: Curves.easeInOut,
          );
    }

    if (message != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          mascot,
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.charcoal.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              message!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.rosePink,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      );
    }

    return mascot;
  }
}
