import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Teacher/Admin Design Constants
/// Based on Lumi_Teacher_UI_Spec.md
///
/// Provides spec-exact typography, dimensions, and decodable tier data
/// for all teacher and admin screens.

// ============================================
// TYPOGRAPHY
// ============================================

class TeacherTypography {
  static const String _fontFamily = 'Nunito';

  // Headings
  static const TextStyle h1 = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.charcoal,
  );

  static const TextStyle h2 = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.charcoal,
  );

  static const TextStyle h3 = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.charcoal,
  );

  // Body
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.charcoal,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.charcoal,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  // Special
  static const TextStyle statValue = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: AppColors.charcoal,
  );

  static const TextStyle buttonText = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.white,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
  );

  static const TextStyle sectionHeader = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: AppColors.teacherPrimary,
    letterSpacing: 0.8,
  );
}

// ============================================
// DIMENSIONS
// ============================================

class TeacherDimensions {
  // Padding
  static const double paddingXS = 4.0;
  static const double paddingS = 8.0;
  static const double paddingM = 12.0;
  static const double paddingL = 16.0;
  static const double paddingXL = 20.0;
  static const double paddingXXL = 24.0;

  // Border Radius
  static const double radiusS = 8.0;
  static const double radiusM = 12.0;
  static const double radiusL = 18.0;
  static const double radiusXL = 24.0;
  static const double radiusRound = 50.0;

  // Avatar Sizes
  static const double avatarS = 40.0;
  static const double avatarM = 64.0;
  static const double avatarL = 80.0;

  // Icon Sizes
  static const double iconS = 18.0;
  static const double iconM = 24.0;
  static const double iconL = 36.0;

  // Card Shadow
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: AppColors.teacherPrimary.withValues(alpha: 0.10),
          blurRadius: 28,
          spreadRadius: -8,
          offset: const Offset(0, 14),
        ),
        BoxShadow(
          color: AppColors.charcoal.withValues(alpha: 0.05),
          blurRadius: 10,
          spreadRadius: -6,
          offset: const Offset(0, 4),
        ),
      ];
}

// ============================================
// DECODABLE TIERS
// ============================================

class DecodableTier {
  final int level;
  final String name;
  final Color color;
  final List<String> exampleWords;

  const DecodableTier({
    required this.level,
    required this.name,
    required this.color,
    this.exampleWords = const [],
  });
}

const List<DecodableTier> decodableTiers = [
  DecodableTier(
    level: 1,
    name: 'CVC Words',
    color: AppColors.levelCVC,
    exampleWords: ['cat', 'hop', 'big'],
  ),
  DecodableTier(
    level: 2,
    name: 'Digraphs',
    color: AppColors.levelDigraphs,
    exampleWords: ['ship', 'chip', 'fish'],
  ),
  DecodableTier(
    level: 3,
    name: 'Blends',
    color: AppColors.levelBlends,
    exampleWords: ['frog', 'drum', 'clap'],
  ),
  DecodableTier(
    level: 4,
    name: 'CVCE (Magic E)',
    color: AppColors.levelCVCE,
    exampleWords: ['cake', 'bike', 'home'],
  ),
  DecodableTier(
    level: 5,
    name: 'Vowel Teams',
    color: AppColors.levelVowelTeams,
    exampleWords: ['rain', 'boat', 'team'],
  ),
  DecodableTier(
    level: 6,
    name: 'R-Controlled',
    color: AppColors.levelRControlled,
    exampleWords: ['car', 'her', 'bird'],
  ),
];
