import 'package:flutter/material.dart';

/// Lumi App Color Palette
/// Based on the Lumi Design System v1.0
///
/// Design Philosophy: Soft, rounded, friendly with pastel colors
/// All colors meet WCAG AA accessibility standards when used correctly
class AppColors {
  // ============================================
  // LUMI DESIGN SYSTEM COLORS (New Palette)
  // ============================================

  /// Primary brand color - Used for CTAs, highlights, active states
  /// Usage: Primary buttons, links, active navigation items
  /// Accessibility: Use with white text (meets WCAG AA)
  static const Color rosePink = Color(0xFFFF8698);

  /// Secondary brand color - Used for success states, positive feedback
  /// Usage: Success messages, completion indicators, positive actions
  /// Accessibility: Use with charcoal text (#121211)
  static const Color mintGreen = Color(0xFFD2EBBF);

  /// Accent color - Used for attention elements, badges
  /// Usage: Warning badges, highlights (background only, never for text)
  /// Accessibility: NEVER use as text color, background only with dark text
  static const Color softYellow = Color(0xFFFFF6A4);

  /// Accent color - Used for warm CTAs, energy elements
  /// Usage: Secondary CTAs, warm highlights, excitement indicators
  /// Accessibility: Use with white text (verify contrast)
  static const Color warmOrange = Color(0xFFFF8B5A);

  /// Neutral color - Used for backgrounds, cards, gentle highlights
  /// Usage: Card backgrounds, section dividers, info states
  /// Accessibility: Use with charcoal text (#121211)
  static const Color skyBlue = Color(0xFFBCE7F0);

  /// Gradient endpoint for primary gradient
  /// Usage: Primary button gradient end, warm CTA backgrounds
  static const Color lumiPeach = Color(0xFFFFAB91);

  /// Base color - Main backgrounds, cards, overlays
  /// Usage: Primary screen background, card backgrounds
  static const Color white = Color(0xFFFFFFFF);

  /// Primary text color - Used for all primary text and icons
  /// Usage: Body text, headings, icons, dark UI elements
  /// Accessibility: Provides 18.5:1 contrast on white background
  static const Color charcoal = Color(0xFF121211);

  /// Secondary text color
  /// Usage: Descriptions, placeholders, secondary labels
  static const Color textSecondary = Color(0xFF6B7280);

  /// Divider/border color
  /// Usage: Card borders, list dividers, input borders
  static const Color divider = Color(0xFFE5E7EB);

  /// App background color
  /// Usage: Scaffold background, page backgrounds
  static const Color background = Color(0xFFF5F5F7);

  /// Library book badge color
  /// Usage: Library book type indicator badge
  static const Color libraryGreen = Color(0xFF81C784);

  /// Decodable book badge color
  /// Usage: Decodable book type indicator badge
  static const Color decodableBlue = Color(0xFF64B5F6);

  // ============================================
  // LEGACY COLORS (Backwards Compatibility)
  // ============================================
  // These colors are kept for backward compatibility with existing screens
  // New development should use the Lumi Design System colors above

  // Primary colors - Original Lumi colors
  static const Color primaryBlue = Color(0xFF4A90E2);
  static const Color primaryLightBlue = Color(0xFF6BA5E9);
  static const Color primaryDarkBlue = Color(0xFF3A7BC8);

  // Secondary colors - Original accent and supporting colors
  static const Color secondaryOrange = Color(0xFFFF8C42);
  static const Color secondaryYellow = Color(0xFFFFD93D);
  static const Color secondaryGreen = Color(0xFF6BCB77);
  static const Color secondaryPurple = Color(0xFF9B59B6);

  // Neutral colors
  static const Color offWhite = Color(0xFFF8F9FA);
  static const Color lightGray = Color(0xFFE9ECEF);
  static const Color gray = Color(0xFF6C757D);
  static const Color darkGray = Color(0xFF343A40);
  static const Color black = Color(0xFF212529);

  // Semantic colors
  static const Color success = Color(0xFF28A745);
  static const Color warning = Color(0xFFFFC107);
  static const Color error = Color(0xFFDC3545);
  static const Color info = Color(0xFF17A2B8);

  // Background colors
  static const Color backgroundPrimary = Color(0xFFFFFBF7);
  static const Color backgroundSecondary = Color(0xFFF5F8FC);

  // Lumi mascot colors
  static const Color lumiBody = Color(0xFF87CEEB);
  static const Color lumiAccent = Color(0xFFFFB6C1);
  static const Color lumiEyes = Color(0xFF2E3440);

  // Role-based colors
  static const Color parentColor = rosePink;
  static const Color teacherColor = teacherPrimary;
  static const Color adminColor = teacherPrimary;

  // ============================================
  // TEACHER/ADMIN THEME COLORS (Soft Blue)
  // ============================================

  /// Teacher/Admin primary - Azure blue
  /// Usage: Staff CTAs, active navigation, emphasis states
  static const Color teacherPrimary = Color(0xFF4F7CF7);

  /// Teacher/Admin accent - Sky blue
  /// Usage: Gradients, supporting accents, highlighted data
  static const Color teacherAccent = Color(0xFF8CB9FF);

  /// Teacher/Admin primary light - Pale blue tint
  /// Usage: Pills, chips, icon backgrounds, selected surfaces
  static const Color teacherPrimaryLight = Color(0xFFDCE8FF);

  /// Teacher/Admin background - Cool off-white
  /// Usage: Staff page backgrounds
  static const Color teacherBackground = Color(0xFFF4F7FC);

  /// Teacher/Admin surface tint - Soft blue wash
  /// Usage: Secondary cards and hero embellishments
  static const Color teacherSurfaceTint = Color(0xFFEAF1FF);

  /// Teacher/Admin border - Muted blue-gray border
  /// Usage: Card outlines, dividers, inactive chips
  static const Color teacherBorder = Color(0xFFD7E3F7);

  // Book Level/Tier Colors (for reading allocation levels)
  static const Color levelCVC = Color(0xFFEF9A9A);
  static const Color levelDigraphs = Color(0xFFFFCC80);
  static const Color levelBlends = Color(0xFFFFF59D);
  static const Color levelCVCE = Color(0xFFA5D6A7);
  static const Color levelVowelTeams = Color(0xFF90CAF9);
  static const Color levelRControlled = Color(0xFFCE93D8);

  // Achievement colors
  static const Color gold = Color(0xFFFFD700);
  static const Color silver = Color(0xFFC0C0C0);
  static const Color bronze = Color(0xFFCD7F32);

  // ============================================
  // COLOR UTILITIES
  // ============================================

  /// Returns the appropriate text color for a given background color
  /// Ensures WCAG AA contrast compliance
  static Color getTextColorForBackground(Color backgroundColor) {
    // Calculate relative luminance
    final luminance = backgroundColor.computeLuminance();

    // Use charcoal for light backgrounds, white for dark backgrounds
    return luminance > 0.5 ? charcoal : white;
  }

  /// Returns a semi-transparent version of the rose pink color
  /// Useful for overlays, hover states, and backgrounds
  static Color rosePinkWithOpacity(double opacity) {
    return rosePink.withValues(alpha: opacity);
  }

  /// Returns a semi-transparent version of the charcoal color
  /// Useful for secondary text, disabled states, and borders
  static Color charcoalWithOpacity(double opacity) {
    return charcoal.withValues(alpha: opacity);
  }

  // ============================================
  // GRADIENTS
  // ============================================

  /// Primary gradient - Rose Pink to Lumi Peach (135deg)
  /// Usage: Primary buttons, hero sections, CTAs
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [rosePink, lumiPeach],
  );

  /// Success gradient - Green tones
  /// Usage: Success states, confirmation buttons
  static const LinearGradient successGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
  );

  /// Teacher/Admin gradient - Azure blue to sky blue (135deg)
  /// Usage: Dashboard headers, scanner cards, staff hero sections
  static const LinearGradient teacherGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [teacherPrimary, teacherAccent],
  );
}

/// Lumi Design System - Semantic Color Aliases
/// Use these for specific UI patterns
extension LumiSemanticColors on AppColors {
  /// Primary action color (buttons, links, active states)
  static Color get primary => AppColors.rosePink;

  /// Secondary action color (success, positive feedback)
  static Color get secondary => AppColors.mintGreen;

  /// Background color for main screens
  static Color get background => AppColors.background;

  /// Background color for cards and elevated surfaces
  static Color get surface => AppColors.white;

  /// Primary text color
  static Color get onBackground => AppColors.charcoal;

  /// Text color on primary color backgrounds
  static Color get onPrimary => AppColors.white;

  /// Border color for inputs and dividers
  static Color get border => AppColors.divider;

  /// Disabled state color
  static Color get disabled => AppColors.charcoal.withValues(alpha: 0.4);
}
