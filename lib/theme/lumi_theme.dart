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

      // ─── Component themes ───────────────────────────────────────────
      // These exist so that an *unstyled* Material widget dropped into a
      // new feature inherits Lumi, not the legacy rose-pink palette. Before
      // this theme was wired into MaterialApp, every bare FilledButton /
      // TextButton / AlertDialog rendered in the old brand colour, which is
      // why new work kept drifting back to the previous design language.

      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: LumiTokens.cream,
        surfaceTintColor: LumiTokens.cream,
        foregroundColor: LumiTokens.ink,
        iconTheme: const IconThemeData(color: LumiTokens.ink),
        titleTextStyle: LumiType.subhead,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: LumiTokens.red,
          foregroundColor: LumiTokens.paper,
          disabledBackgroundColor: LumiTokens.tintRed,
          disabledForegroundColor: LumiTokens.paper,
          minimumSize: const Size(0, 56),
          padding: const EdgeInsets.symmetric(
            horizontal: LumiTokens.space5,
            vertical: LumiTokens.space4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
          ),
          textStyle: LumiType.button,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: LumiTokens.red,
          foregroundColor: LumiTokens.paper,
          minimumSize: const Size(0, 56),
          padding: const EdgeInsets.symmetric(
            horizontal: LumiTokens.space5,
            vertical: LumiTokens.space4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
          ),
          textStyle: LumiType.button,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: LumiTokens.ink,
          backgroundColor: LumiTokens.paper,
          minimumSize: const Size(0, 56),
          padding: const EdgeInsets.symmetric(
            horizontal: LumiTokens.space5,
            vertical: LumiTokens.space4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
          ),
          side: const BorderSide(color: LumiTokens.rule, width: 1.5),
          textStyle: LumiType.button,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: LumiTokens.ink,
          padding: const EdgeInsets.symmetric(
            horizontal: LumiTokens.space4,
            vertical: LumiTokens.space2,
          ),
          textStyle: LumiType.button,
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: LumiTokens.paper,
        surfaceTintColor: LumiTokens.paper,
        shadowColor: LumiTokens.ink.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
          side: const BorderSide(color: LumiTokens.rule),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: LumiTokens.paper,
        surfaceTintColor: LumiTokens.paper,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
          side: const BorderSide(color: LumiTokens.rule),
        ),
        titleTextStyle: LumiType.subhead,
        contentTextStyle: LumiType.body,
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: LumiTokens.paper,
        surfaceTintColor: LumiTokens.paper,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(LumiTokens.radiusXL),
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: LumiTokens.cream,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
          borderSide: const BorderSide(color: LumiTokens.rule),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
          borderSide: const BorderSide(color: LumiTokens.rule),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
          borderSide: const BorderSide(color: LumiTokens.ink, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
          borderSide: const BorderSide(color: LumiTokens.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
          borderSide: const BorderSide(color: LumiTokens.red, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: LumiTokens.space4,
          vertical: LumiTokens.space4,
        ),
        labelStyle: LumiType.caption,
        hintStyle: LumiType.caption.copyWith(color: LumiTokens.muted),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        elevation: 0,
        backgroundColor: LumiTokens.paper,
        selectedItemColor: LumiTokens.red,
        unselectedItemColor: LumiTokens.muted,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: LumiType.caption,
        unselectedLabelStyle: LumiType.caption,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: LumiTokens.cream,
        disabledColor: LumiTokens.rule,
        selectedColor: LumiTokens.tintBlue,
        padding: const EdgeInsets.symmetric(
          horizontal: LumiTokens.space3,
          vertical: LumiTokens.space2,
        ),
        labelStyle: LumiType.caption,
        side: const BorderSide(color: LumiTokens.rule),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: LumiTokens.rule,
        thickness: 1,
        space: 1,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: LumiTokens.ink,
        contentTextStyle: LumiType.body.copyWith(color: LumiTokens.paper),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        ),
        behavior: SnackBarBehavior.fixed,
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: LumiTokens.red,
        linearTrackColor: LumiTokens.rule,
        circularTrackColor: LumiTokens.rule,
      ),

      // Default section: Home (red). Screens override with LumiSectionScope.
      extensions: const [LumiSectionTheme.home],
    );
  }
}
