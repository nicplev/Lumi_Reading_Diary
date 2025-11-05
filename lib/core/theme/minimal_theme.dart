/// Minimal Purple Design System
/// Soft purple and cream colour palette with rounded cards and clean typography
library;

import 'package:flutter/material.dart';

class MinimalTheme {
  // Colours
  static const Color primaryPurple = Color(0xFFAA86F8);
  static const Color lightPurple = Color(0xFFE8E0F8);
  static const Color cream = Color(0xFFE6E6DE);
  static const Color darkPurple = Color(0xFF8B5CF6);
  static const Color orange = Color(0xFFFBBC1D);
  static const Color green = Color(0xFF4ADE80);
  static const Color blue = Color(0xFF3B82F6);
  static const Color red = Color(0xFFEF4444);
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color white = Color(0xFFFFFFFF);
  static const Color gold = Color(0xFFFFD700);

  // Border Radius
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 20.0;
  static const double radiusXLarge = 24.0;
  static const double radiusPill = 100.0;

  // Spacing
  static const double spaceXS = 4.0;
  static const double spaceS = 8.0;
  static const double spaceM = 16.0;
  static const double spaceL = 24.0;
  static const double spaceXL = 32.0;
  static const double spaceXXL = 40.0;

  // Shadows
  static List<BoxShadow> cardShadow() {
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 10,
        offset: const Offset(0, 2),
      ),
    ];
  }

  static List<BoxShadow> softShadow() {
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.06),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ];
  }

  // Gradients
  static const LinearGradient purpleGradient = LinearGradient(
    colors: [primaryPurple, darkPurple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [green, Color(0xFF22C55E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient warmGradient = LinearGradient(
    colors: [orange, Color(0xFFF59E0B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [cream, Color(0xFFF5F5ED)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Theme Data
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: primaryPurple,
      secondary: lightPurple,
      surface: white,
      error: red,
    ),
    scaffoldBackgroundColor: cream,
    fontFamily: 'SF Pro Display',
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: textPrimary,
        height: 1.2,
      ),
      displayMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: textPrimary,
        height: 1.2,
      ),
      headlineLarge: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        color: textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        color: textSecondary,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: textSecondary,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLarge),
      ),
      color: white,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryPurple,
        foregroundColor: white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusPill),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: primaryPurple, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: spaceM,
        vertical: spaceM,
      ),
    ),
  );
}
