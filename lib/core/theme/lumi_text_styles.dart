import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Lumi Design System - Typography
///
/// All text styles use Nunito font family with specific weights:
/// - Regular: 400 (body text, captions)
/// - Semi-Bold: 600 (buttons, labels, subheadings)
/// - Bold: 700 (headings, emphasis)
///
/// Type Scale:
/// Display: 36pt | H1: 28pt | H2: 24pt | H3: 20pt
/// Body Large: 18pt | Body: 16pt | Small: 14pt | Caption: 12pt
class LumiTextStyles {
  // Base font family
  static const String fontFamily = 'Nunito';

  // ============================================
  // DISPLAY TEXT (Hero sections, large headings)
  // ============================================

  /// Display text - 36pt Bold
  /// Usage: Hero sections, splash screens, large marketing text
  /// Line height: 1.2
  static TextStyle display({Color? color}) => GoogleFonts.nunito(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.charcoal,
        height: 1.2,
        letterSpacing: -0.5,
      );

  /// Display medium - 32pt Bold
  /// Usage: Large section headings
  /// Line height: 1.25
  static TextStyle displayMedium({Color? color}) => GoogleFonts.nunito(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.charcoal,
        height: 1.25,
        letterSpacing: -0.5,
      );

  // ============================================
  // HEADINGS
  // ============================================

  /// Heading 1 - 28pt Bold
  /// Usage: Page titles, main headings
  /// Line height: 1.3
  static TextStyle h1({Color? color}) => GoogleFonts.nunito(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.charcoal,
        height: 1.3,
        letterSpacing: -0.5,
      );

  /// Heading 2 - 24pt Semi-Bold
  /// Usage: Section headings, card titles
  /// Line height: 1.3
  static TextStyle h2({Color? color}) => GoogleFonts.nunito(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.charcoal,
        height: 1.3,
      );

  /// Heading 3 - 20pt Semi-Bold
  /// Usage: Sub-section headings, list headers
  /// Line height: 1.4
  static TextStyle h3({Color? color}) => GoogleFonts.nunito(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.charcoal,
        height: 1.4,
      );

  // ============================================
  // BODY TEXT
  // ============================================

  /// Body Large - 18pt Regular
  /// Usage: Important body text, introductions
  /// Line height: 1.5
  static TextStyle bodyLarge({Color? color}) => GoogleFonts.nunito(
        fontSize: 18,
        fontWeight: FontWeight.w400,
        color: color ?? AppColors.charcoal,
        height: 1.5,
      );

  /// Body - 16pt Regular
  /// Usage: Default body text, most content
  /// Line height: 1.5
  static TextStyle body({Color? color}) => GoogleFonts.nunito(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: color ?? AppColors.charcoal,
        height: 1.5,
      );

  /// Body Medium - 16pt Semi-Bold
  /// Usage: Emphasized body text, labels
  /// Line height: 1.5
  static TextStyle bodyMedium({Color? color}) => GoogleFonts.nunito(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.charcoal,
        height: 1.5,
      );

  /// Body Small - 14pt Regular
  /// Usage: Secondary text, descriptions
  /// Line height: 1.5
  static TextStyle bodySmall({Color? color}) => GoogleFonts.nunito(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: color ?? AppColors.charcoal,
        height: 1.5,
      );

  // ============================================
  // CAPTIONS & LABELS
  // ============================================

  /// Caption - 12pt Regular
  /// Usage: Timestamps, hints, supplementary info
  /// Line height: 1.4
  static TextStyle caption({Color? color}) => GoogleFonts.nunito(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: color ?? AppColors.charcoal.withOpacity(0.7),
        height: 1.4,
      );

  /// Label - 14pt Semi-Bold
  /// Usage: Form labels, tab labels, button text (small)
  /// Line height: 1.4
  static TextStyle label({Color? color}) => GoogleFonts.nunito(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.charcoal,
        height: 1.4,
      );

  // ============================================
  // BUTTON TEXT
  // ============================================

  /// Button - 16pt Semi-Bold
  /// Usage: Primary and secondary button labels
  /// Line height: 1.2
  static TextStyle button({Color? color}) => GoogleFonts.nunito(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.white,
        height: 1.2,
        letterSpacing: 0.5,
      );

  /// Button Small - 14pt Semi-Bold
  /// Usage: Compact buttons, chips
  /// Line height: 1.2
  static TextStyle buttonSmall({Color? color}) => GoogleFonts.nunito(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.white,
        height: 1.2,
        letterSpacing: 0.5,
      );

  // ============================================
  // SPECIAL PURPOSE
  // ============================================

  /// Overline - 12pt Semi-Bold, UPPERCASE
  /// Usage: Section labels, category tags
  /// Line height: 1.2
  static TextStyle overline({Color? color}) => GoogleFonts.nunito(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.charcoal.withOpacity(0.7),
        height: 1.2,
        letterSpacing: 1.5,
      ).copyWith(
        // Force uppercase
        fontFeatures: const [FontFeature.enable('smcp')],
      );

  /// Link - 16pt Semi-Bold with underline
  /// Usage: Inline links, navigation links
  /// Line height: 1.5
  static TextStyle link({Color? color}) => GoogleFonts.nunito(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.rosePink,
        height: 1.5,
        decoration: TextDecoration.underline,
        decorationColor: color ?? AppColors.rosePink,
      );

  // ============================================
  // THEMED TEXT STYLES
  // ============================================

  /// Text style for error messages
  static TextStyle error() => bodySmall(color: AppColors.error);

  /// Text style for success messages
  static TextStyle success() => bodySmall(color: AppColors.success);

  /// Text style for warning messages
  static TextStyle warning() => bodySmall(color: AppColors.warning);

  /// Text style for disabled text
  static TextStyle disabled() => body(color: AppColors.charcoal.withOpacity(0.4));

  /// Text style for secondary/muted text
  static TextStyle secondary() => body(color: AppColors.charcoal.withOpacity(0.7));
}

/// Extension for easy access to text styles from BuildContext
extension LumiTextStylesContext on BuildContext {
  /// Access Lumi text styles
  LumiTextStyles get textStyles => LumiTextStyles();
}

/// Convenience class for text style access
class LumiTextStylesInstance {
  // Display
  TextStyle get display => LumiTextStyles.display();
  TextStyle get displayMedium => LumiTextStyles.displayMedium();

  // Headings
  TextStyle get h1 => LumiTextStyles.h1();
  TextStyle get h2 => LumiTextStyles.h2();
  TextStyle get h3 => LumiTextStyles.h3();

  // Body
  TextStyle get bodyLarge => LumiTextStyles.bodyLarge();
  TextStyle get body => LumiTextStyles.body();
  TextStyle get bodyMedium => LumiTextStyles.bodyMedium();
  TextStyle get bodySmall => LumiTextStyles.bodySmall();

  // Captions
  TextStyle get caption => LumiTextStyles.caption();
  TextStyle get label => LumiTextStyles.label();

  // Buttons
  TextStyle get button => LumiTextStyles.button();
  TextStyle get buttonSmall => LumiTextStyles.buttonSmall();

  // Special
  TextStyle get overline => LumiTextStyles.overline();
  TextStyle get link => LumiTextStyles.link();

  // Themed
  TextStyle get error => LumiTextStyles.error();
  TextStyle get success => LumiTextStyles.success();
  TextStyle get warning => LumiTextStyles.warning();
  TextStyle get disabled => LumiTextStyles.disabled();
  TextStyle get secondary => LumiTextStyles.secondary();
}
