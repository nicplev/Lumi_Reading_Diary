import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Liquid Glass Design System
/// Follows Apple's glass specifications with 30px blur and 18% opacity
class LiquidGlassTheme {
  LiquidGlassTheme._(); // Private constructor to prevent instantiation

  // ============================================
  // GLASS PROPERTIES
  // ============================================

  /// Backdrop blur amount (30px as per Apple specs)
  static const double glassBlur = 30.0;

  /// Glass opacity for light mode (18% as per Apple specs)
  static const double glassOpacityLight = 0.18;

  /// Glass opacity for dark mode
  static const double glassOpacityDark = 0.15;

  // ============================================
  // SPACING SYSTEM
  // ============================================

  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;
  static const double spacingXxl = 48.0;

  // ============================================
  // BORDER RADIUS SYSTEM
  // ============================================

  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;
  static const double radiusCapsule = 999.0;

  // ============================================
  // GRADIENTS
  // ============================================

  /// Background gradient for app
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFE8F4F8), // Light blue
      Color(0xFFF5E6FF), // Light purple
      Color(0xFFFFE8F0), // Light pink
    ],
  );

  /// Warm gradient (red to orange)
  static const LinearGradient warmGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFF6B6B), // Red
      Color(0xFFFFAA5C), // Orange
    ],
  );

  /// Cool gradient (blue to purple)
  static const LinearGradient coolGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.primaryBlue,
      AppColors.secondaryPurple,
    ],
  );

  /// Success gradient (green shades)
  static const LinearGradient successGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF4CAF50), // Green
      Color(0xFF66BB6A), // Light green
    ],
  );

  /// Purple gradient
  static const LinearGradient purpleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF9C27B0), // Purple
      Color(0xFFBA68C8), // Light purple
    ],
  );

  /// Reading gradient (warm colors)
  static const LinearGradient readingGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.secondaryOrange,
      AppColors.secondaryYellow,
    ],
  );

  /// Teacher gradient
  static const LinearGradient teacherGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.teacherColor,
      Color(0xFF66BB6A),
    ],
  );

  /// Parent gradient
  static const LinearGradient parentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.parentColor,
      Color(0xFF42A5F5),
    ],
  );

  /// Admin gradient
  static const LinearGradient adminGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.adminColor,
      Color(0xFFEF5350),
    ],
  );

  // ============================================
  // HELPER METHODS
  // ============================================

  /// Creates a glass decoration with backdrop blur
  static BoxDecoration glassDecoration({
    double borderRadius = radiusLg,
    Color? color,
    Border? border,
  }) {
    return BoxDecoration(
      color: color ?? Colors.white.withOpacity(glassOpacityLight),
      borderRadius: BorderRadius.circular(borderRadius),
      border: border ??
          Border.all(
            color: Colors.white.withOpacity(0.3),
            width: 1.5,
          ),
    );
  }

  /// Creates a gradient decoration
  static BoxDecoration gradientDecoration({
    required Gradient gradient,
    double borderRadius = radiusLg,
    Border? border,
  }) {
    return BoxDecoration(
      gradient: gradient,
      borderRadius: BorderRadius.circular(borderRadius),
      border: border,
    );
  }

  /// Creates a glass container widget
  static Widget glassContainer({
    required Widget child,
    double borderRadius = radiusLg,
    EdgeInsetsGeometry? padding,
    Color? color,
    double? width,
    double? height,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: glassBlur, sigmaY: glassBlur),
        child: Container(
          width: width,
          height: height,
          padding: padding ?? const EdgeInsets.all(spacingMd),
          decoration: glassDecoration(
            borderRadius: borderRadius,
            color: color,
          ),
          child: child,
        ),
      ),
    );
  }

  /// Creates gradient text shader
  static ShaderMask gradientText({
    required Widget child,
    required Gradient gradient,
  }) {
    return ShaderMask(
      shaderCallback: (bounds) => gradient.createShader(bounds),
      child: child,
    );
  }

  /// Creates a glow effect
  static List<BoxShadow> glowShadow({
    required Color color,
    double blurRadius = 20.0,
    double spreadRadius = 2.0,
  }) {
    return [
      BoxShadow(
        color: color.withOpacity(0.3),
        blurRadius: blurRadius,
        spreadRadius: spreadRadius,
      ),
    ];
  }

  /// Creates soft shadow
  static List<BoxShadow> softShadow() {
    return [
      BoxShadow(
        color: Colors.black.withOpacity(0.05),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ];
  }
}
