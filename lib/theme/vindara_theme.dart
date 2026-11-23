// lib/theme/vindara_theme.dart
//
// Vindara — High-Contrast Accessible Material 3 Theme
// Package: com.vindara.app
//
// Design principles:
//   - High-stress readability: clear typography, bold weights, high-contrast ratios.
//   - Emergency priority red (#D32F2F) with calming dark/light surface balances.
//   - Min touch targets: 48dp+ for critical actions.

import 'package:flutter/material.dart';

abstract class VindaraTheme {
  VindaraTheme._();

  static const Color emergencyRed = Color(0xFFD32F2F);
  static const Color emergencyDarkRed = Color(0xFFB71C1C);
  static const Color emergencyLightRed = Color(0xFFFFEBEE);

  static const Color statusAlerting = Color(0xFFE65100);
  static const Color statusAccepted = Color(0xFF0277BD);
  static const Color statusInProgress = Color(0xFF6A1B9A);
  static const Color statusResolved = Color(0xFF2E7D32);
  static const Color statusCancelled = Color(0xFF616161);

  static const Color official112Color = Color(0xFF1565C0);

  static ThemeData lightTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: emergencyRed,
      primary: emergencyRed,
      onPrimary: Colors.white,
      secondary: const Color(0xFF37474F),
      onSecondary: Colors.white,
      error: emergencyDarkRed,
      surface: const Color(0xFFFBFBFB),
      onSurface: const Color(0xFF212121),
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF5F6F8),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF212121),
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Color(0xFF212121),
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: const BorderSide(color: Color(0xFFB0BEC5), width: 1.5),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
