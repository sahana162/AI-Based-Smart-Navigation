import 'package:flutter/material.dart';

class AppTheme {
  // High contrast color palette tailored for visual impairment & low vision
  static const Color background = Color(0xFF0F141C);
  static const Color surface = Color(0xFF1B2330);
  static const Color surfaceHighlight = Color(0xFF283446);
  static const Color primary = Color(0xFFFFC107); // High-contrast warm amber
  static const Color primaryDark = Color(0xFFFFA000);
  static const Color onPrimary = Color(0xFF000000);
  static const Color accentCyan = Color(0xFF00E5FF); // Electric cyan for secondary actions
  static const Color accentYellow = Color(0xFFFFEB3B); // Safety bright yellow
  static const Color textPrimary = Color(0xFFFFFFFF); // High-contrast pure white
  static const Color textSecondary = Color(0xFFE2E8F0); // Very light grey
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color success = Color(0xFF00E676);
  static const Color danger = Color(0xFFFF5252);
  static const Color border = Color(0xFF334155);

  static ThemeData get highContrastDarkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        onPrimary: onPrimary,
        secondary: accentCyan,
        onSecondary: Color(0xFF000000),
        surface: surface,
        onSurface: textPrimary,
        error: danger,
        onError: Color(0xFF000000),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          letterSpacing: 0.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          letterSpacing: 0.3,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w400,
          color: textPrimary,
          height: 1.4,
        ),
        bodyMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: textSecondary,
          height: 1.4,
        ),
        labelLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: 0.5,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
      ),
    );
  }
}
