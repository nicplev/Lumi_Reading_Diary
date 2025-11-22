import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Lumi Design System - Border Radius & Borders
///
/// All border radius values follow the Lumi design system
/// Use soft, rounded corners throughout the app
///
/// Radius Values:
/// Small: 8pt  - Small elements, chips, tags
/// Medium: 12pt - Buttons, inputs, most interactive elements
/// Large: 16pt  - Cards, containers, modals
/// XLarge: 24pt - Large modals, bottom sheets
class LumiBorders {
  // ============================================
  // BORDER RADIUS VALUES
  // ============================================

  /// Small radius - 8pt
  /// Usage: Small buttons, chips, tags, icon containers
  static const double radiusSmall = 8.0;

  /// Medium radius - 12pt
  /// Usage: Primary buttons, inputs, most interactive elements
  static const double radiusMedium = 12.0;

  /// Large radius - 16pt
  /// Usage: Cards, containers, list items
  static const double radiusLarge = 16.0;

  /// Extra large radius - 24pt
  /// Usage: Large modals, bottom sheets, hero sections
  static const double radiusXLarge = 24.0;

  /// Circular radius (for perfect circles)
  /// Usage: Avatars, icon buttons, floating action buttons
  static const double radiusCircular = 999.0;

  // ============================================
  // BORDERRADIUS PRESETS
  // ============================================

  /// Small border radius - 8pt (all corners)
  static const BorderRadius small = BorderRadius.all(Radius.circular(radiusSmall));

  /// Medium border radius - 12pt (all corners)
  static const BorderRadius medium = BorderRadius.all(Radius.circular(radiusMedium));

  /// Large border radius - 16pt (all corners)
  static const BorderRadius large = BorderRadius.all(Radius.circular(radiusLarge));

  /// Extra large border radius - 24pt (all corners)
  static const BorderRadius xLarge = BorderRadius.all(Radius.circular(radiusXLarge));

  /// Circular border radius (perfect circle)
  static const BorderRadius circular = BorderRadius.all(Radius.circular(radiusCircular));

  // ============================================
  // PARTIAL BORDER RADIUS (Common Patterns)
  // ============================================

  /// Top corners rounded (medium) - for bottom sheets, modals
  static const BorderRadius topMedium = BorderRadius.only(
    topLeft: Radius.circular(radiusMedium),
    topRight: Radius.circular(radiusMedium),
  );

  /// Top corners rounded (large) - for bottom sheets, modals
  static const BorderRadius topLarge = BorderRadius.only(
    topLeft: Radius.circular(radiusLarge),
    topRight: Radius.circular(radiusLarge),
  );

  /// Top corners rounded (x-large) - for bottom sheets, modals
  static const BorderRadius topXLarge = BorderRadius.only(
    topLeft: Radius.circular(radiusXLarge),
    topRight: Radius.circular(radiusXLarge),
  );

  /// Bottom corners rounded (medium)
  static const BorderRadius bottomMedium = BorderRadius.only(
    bottomLeft: Radius.circular(radiusMedium),
    bottomRight: Radius.circular(radiusMedium),
  );

  /// Bottom corners rounded (large)
  static const BorderRadius bottomLarge = BorderRadius.only(
    bottomLeft: Radius.circular(radiusLarge),
    bottomRight: Radius.circular(radiusLarge),
  );

  // ============================================
  // BORDER PRESETS
  // ============================================

  /// Default border - 1pt solid, 10% opacity charcoal
  /// Usage: Dividers, subtle separators
  static final Border defaultBorder = Border.all(
    color: AppColors.charcoal.withOpacity(0.1),
    width: 1.0,
  );

  /// Input border - 2pt solid, 10% opacity charcoal
  /// Usage: Input fields, form elements
  static final Border inputBorder = Border.all(
    color: AppColors.charcoal.withOpacity(0.1),
    width: 2.0,
  );

  /// Primary border - 2pt solid, rose pink
  /// Usage: Primary buttons, focused elements
  static const Border primaryBorder = Border.fromBorderSide(
    BorderSide(
      color: AppColors.rosePink,
      width: 2.0,
    ),
  );

  /// Error border - 2pt solid, error red
  /// Usage: Error states, validation failures
  static const Border errorBorder = Border.fromBorderSide(
    BorderSide(
      color: AppColors.error,
      width: 2.0,
    ),
  );

  /// Success border - 2pt solid, mint green
  /// Usage: Success states, completed items
  static const Border successBorder = Border.fromBorderSide(
    BorderSide(
      color: AppColors.mintGreen,
      width: 2.0,
    ),
  );

  // ============================================
  // BOXDECORATION PRESETS
  // ============================================

  /// Card decoration - white background, large radius, subtle shadow
  /// Usage: Standard cards, containers
  static BoxDecoration get card => BoxDecoration(
        color: AppColors.white,
        borderRadius: large,
        boxShadow: [
          BoxShadow(
            color: AppColors.charcoal.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 2),
          ),
        ],
      );

  /// Highlighted card - sky blue background, large radius, subtle shadow
  /// Usage: Selected cards, active states
  static BoxDecoration get cardHighlighted => BoxDecoration(
        color: AppColors.skyBlue,
        borderRadius: large,
        boxShadow: [
          BoxShadow(
            color: AppColors.charcoal.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 2),
          ),
        ],
      );

  /// Input decoration - white background, medium radius, subtle border
  /// Usage: Input fields, form elements
  static BoxDecoration get input => BoxDecoration(
        color: AppColors.white,
        borderRadius: medium,
        border: Border.all(
          color: AppColors.charcoal.withOpacity(0.1),
          width: 2.0,
        ),
      );

  /// Input focused decoration - white background, medium radius, primary border
  /// Usage: Focused input fields
  static BoxDecoration get inputFocused => BoxDecoration(
        color: AppColors.white,
        borderRadius: medium,
        border: const Border.fromBorderSide(
          BorderSide(
            color: AppColors.rosePink,
            width: 2.0,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.rosePink.withOpacity(0.1),
            blurRadius: 0,
            spreadRadius: 4,
          ),
        ],
      );

  /// Button decoration - rose pink background, medium radius, shadow
  /// Usage: Primary buttons
  static BoxDecoration get button => BoxDecoration(
        color: AppColors.rosePink,
        borderRadius: medium,
        boxShadow: [
          BoxShadow(
            color: AppColors.rosePink.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      );

  /// Secondary button decoration - white background, medium radius, primary border
  /// Usage: Secondary buttons
  static BoxDecoration get buttonSecondary => BoxDecoration(
        color: AppColors.white,
        borderRadius: medium,
        border: const Border.fromBorderSide(
          BorderSide(
            color: AppColors.rosePink,
            width: 2.0,
          ),
        ),
      );

  /// Modal decoration - white background, top corners rounded (x-large), shadow
  /// Usage: Bottom sheets, modals
  static BoxDecoration get modal => BoxDecoration(
        color: AppColors.white,
        borderRadius: topXLarge,
        boxShadow: [
          BoxShadow(
            color: AppColors.charcoal.withOpacity(0.16),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
      );

  /// Centered modal decoration - white background, all corners rounded (large), shadow
  /// Usage: Alert dialogs, centered modals
  static BoxDecoration get modalCentered => BoxDecoration(
        color: AppColors.white,
        borderRadius: large,
        boxShadow: [
          BoxShadow(
            color: AppColors.charcoal.withOpacity(0.16),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
      );

  // ============================================
  // SHAPE BORDERS (for ShapeDecoration)
  // ============================================

  /// Rounded rectangle shape border - medium radius
  static const RoundedRectangleBorder shapeMedium = RoundedRectangleBorder(
    borderRadius: medium,
  );

  /// Rounded rectangle shape border - large radius
  static const RoundedRectangleBorder shapeLarge = RoundedRectangleBorder(
    borderRadius: large,
  );

  /// Rounded rectangle shape border with primary border - medium radius
  static const RoundedRectangleBorder shapePrimaryBorder = RoundedRectangleBorder(
    borderRadius: medium,
    side: BorderSide(
      color: AppColors.rosePink,
      width: 2.0,
    ),
  );

  /// Circle shape border
  static const CircleBorder shapeCircle = CircleBorder();

  // ============================================
  // HELPER METHODS
  // ============================================

  /// Create a custom border radius with specific value
  static BorderRadius custom(double radius) {
    return BorderRadius.all(Radius.circular(radius));
  }

  /// Create a custom border with specific color and width
  static Border customBorder({
    required Color color,
    double width = 1.0,
  }) {
    return Border.all(color: color, width: width);
  }

  /// Create a custom BoxDecoration with specific parameters
  static BoxDecoration customDecoration({
    Color? color,
    BorderRadius? borderRadius,
    Border? border,
    List<BoxShadow>? boxShadow,
    Gradient? gradient,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: borderRadius,
      border: border,
      boxShadow: boxShadow,
      gradient: gradient,
    );
  }
}
