import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData lightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: AppColors.primaryBlue,
      scaffoldBackgroundColor: AppColors.backgroundPrimary,

      colorScheme: const ColorScheme.light(
        primary: AppColors.primaryBlue,
        primaryContainer: AppColors.primaryLightBlue,
        secondary: AppColors.secondaryOrange,
        secondaryContainer: AppColors.secondaryYellow,
        surface: AppColors.white,
        surfaceContainerHighest: AppColors.offWhite,
        error: AppColors.error,
        onPrimary: AppColors.white,
        onSecondary: AppColors.white,
        onSurface: AppColors.darkGray,
        onError: AppColors.white,
      ),

      textTheme: TextTheme(
        // Display styles
        displayLarge: GoogleFonts.poppins(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: AppColors.darkGray,
        ),
        displayMedium: GoogleFonts.poppins(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: AppColors.darkGray,
        ),
        displaySmall: GoogleFonts.poppins(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: AppColors.darkGray,
        ),

        // Headline styles
        headlineLarge: GoogleFonts.poppins(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: AppColors.darkGray,
        ),
        headlineMedium: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: AppColors.darkGray,
        ),
        headlineSmall: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.w500,
          color: AppColors.darkGray,
        ),

        // Title styles
        titleLarge: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.darkGray,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppColors.darkGray,
        ),
        titleSmall: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.gray,
        ),

        // Body styles
        bodyLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          color: AppColors.darkGray,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.normal,
          color: AppColors.darkGray,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.normal,
          color: AppColors.gray,
        ),

        // Label styles
        labelLarge: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.darkGray,
        ),
        labelMedium: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.gray,
        ),
        labelSmall: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: AppColors.gray,
        ),
      ),

      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: AppColors.white,
        iconTheme: const IconThemeData(
          color: AppColors.darkGray,
        ),
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.darkGray,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: AppColors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryBlue,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          side: const BorderSide(
            color: AppColors.primaryBlue,
            width: 2,
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryBlue,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        color: AppColors.white,
        surfaceTintColor: AppColors.white,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.offWhite,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.primaryBlue,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.error,
            width: 1,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.error,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        labelStyle: GoogleFonts.inter(
          fontSize: 14,
          color: AppColors.gray,
        ),
        hintStyle: GoogleFonts.inter(
          fontSize: 14,
          color: AppColors.gray.withOpacity(0.6),
        ),
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        elevation: 8,
        backgroundColor: AppColors.white,
        selectedItemColor: AppColors.primaryBlue,
        unselectedItemColor: AppColors.gray,
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: true,
        showUnselectedLabels: true,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.lightGray,
        disabledColor: AppColors.lightGray.withOpacity(0.5),
        selectedColor: AppColors.primaryBlue,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.darkGray,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.lightGray,
        thickness: 1,
        space: 1,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.darkGray,
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14,
          color: AppColors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Add dark theme if needed in the future
  static ThemeData darkTheme() {
    return lightTheme(); // For now, using light theme only
  }
}