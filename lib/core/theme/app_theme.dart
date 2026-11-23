import 'package:flutter/material.dart';

/// Clean, Modern, Light Theme Semantic Palette for Vindara
class AppColors {
  AppColors._();

  // Background & Surfaces (Warm Ivory / Pure White Palette)
  static const Color background = Color(0xFFFAF9F6); // Warm Off-White / Ivory
  static const Color surface = Color(0xFFFFFFFF); // Pure White
  static const Color surfaceMuted = Color(0xFFF3F4F6); // Cool light gray
  static const Color surfaceSubtle = Color(0xFFF3F4F6);
  static const Color surfaceElevated = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFEAE8E3); // Subtle Card Border
  static const Color borderLight = Color(0xFFE5E7EB);
  static const Color borderHighlight = Color(0xFFD1D5DB);
  static const Color divider = Color(0xFFF3F4F6);

  // Inks & Typography
  static const Color textPrimary = Color(0xFF111827); // Deep Slate Black
  static const Color textSecondary = Color(0xFF6B7280); // Cool Gray
  static const Color textTertiary = Color(0xFF9CA3AF);
  static const Color textMuted = Color(0xFFD1D5DB);

  // Semantic Primary HELP Red
  static const Color primaryRed = Color(0xFFDC2626); // Strong Red
  static const Color primaryRedLight = Color(0xFFFEE2E2); // Soft Rose Pill Tint
  static const Color criticalDanger = Color(0xFFDC2626);

  // Semantic Online / WhatsApp Green
  static const Color onlineGreen = Color(0xFF10B981); // Emerald Green
  static const Color greenDark = Color(0xFF059669);
  static const Color greenLight = Color(0xFFD1FAE5); // Soft Mint Pill Tint
  static const Color safe = Color(0xFF10B981);

  // Semantic Official / SMS / Navigation Blue
  static const Color officialBlue = Color(0xFF2563EB); // Royal Blue
  static const Color blueLight = Color(0xFFDBEAFE); // Soft Blue Pill Tint
  static const Color info = Color(0xFF2563EB);

  // Semantic Warning / Offline Amber
  static const Color warningAmber = Color(0xFFF59E0B);
  static const Color amberLight = Color(0xFFFEF3C7);
  static const Color warning = Color(0xFFF59E0B);
}

/// Modern Light Theme System for Vindara
class AppTheme {
  AppTheme._();

  static const String monospaceFont = 'monospace';

  static ThemeData get lightTheme {
    final base = ThemeData.light(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.light(
        brightness: Brightness.light,
        primary: AppColors.primaryRed,
        onPrimary: Colors.white,
        secondary: AppColors.officialBlue,
        onSecondary: Colors.white,
        tertiary: AppColors.onlineGreen,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.primaryRed,
        onError: Colors.white,
        outline: AppColors.border,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border, width: 1),
          borderRadius: BorderRadius.circular(18),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          backgroundColor: AppColors.primaryRed,
          foregroundColor: Colors.white,
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border, width: 1.2),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 20,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 26,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        headlineSmall: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.45,
        ),
        bodyMedium: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w400,
          height: 1.45,
        ),
        bodySmall: TextStyle(
          color: AppColors.textTertiary,
          fontSize: 11,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  /// High-legibility tabular monospace typography for GPS coordinates and countdowns
  static TextStyle get tabularNumericStyle => const TextStyle(
    fontFamily: monospaceFont,
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
    color: AppColors.textSecondary,
  );
}
