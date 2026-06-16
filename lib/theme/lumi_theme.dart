import 'package:flutter/material.dart';
import 'lumi_tokens.dart';
import 'lumi_typography.dart';
import 'section_theme.dart';

class LumiTheme {
  LumiTheme._();

  /// The base ThemeData. Apply this at MaterialApp level.
  /// Individual screens override the section via LumiSectionScope.
  static ThemeData base() {
    return ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      scaffoldBackgroundColor: LumiTokens.cream,

      colorScheme: const ColorScheme.light(
        primary: LumiTokens.red,
        onPrimary: LumiTokens.paper,
        secondary: LumiTokens.ink,
        onSecondary: LumiTokens.paper,
        surface: LumiTokens.paper,
        onSurface: LumiTokens.ink,
        surfaceContainerLowest: LumiTokens.cream,
        surfaceContainerLow: LumiTokens.paper,
        error: LumiTokens.red,
        onError: LumiTokens.paper,
        outline: LumiTokens.rule,
        outlineVariant: LumiTokens.rule,
      ),

      textTheme: TextTheme(
        displayLarge: LumiType.displayXL,
        displayMedium: LumiType.displayL,
        headlineLarge: LumiType.heading,
        headlineMedium: LumiType.subhead,
        titleLarge: LumiType.subhead,
        bodyLarge: LumiType.bodyL,
        bodyMedium: LumiType.body,
        labelLarge: LumiType.button,
        labelMedium: LumiType.sectionLabel,
        labelSmall: LumiType.caption,
      ),

      dividerColor: LumiTokens.rule,

      // Default section: Home (red). Screens override with LumiSectionScope.
      extensions: const [LumiSectionTheme.home],
    );
  }
}
