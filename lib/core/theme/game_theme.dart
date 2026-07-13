import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class GameColors {
  static const background = Color(0xFF0D0B10);
  static const surface = Color(0xFF1A1720);
  static const primary = Color(0xFF7F77DD);
  static const accent = Color(0xFFEF9F27);
  static const textPrimary = Color(0xFFE8E4F0);
  static const textSecondary = Color(0xFF9A94B0);
  static const hpRed = Color(0xFFE53935);
  static const hpGreen = Color(0xFF4CAF50);
  static const cardBorder = Color(0xFF2E2A40);
}

ThemeData buildGameTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: GameColors.background,
    colorScheme: const ColorScheme.dark(
      primary: GameColors.primary,
      secondary: GameColors.accent,
      surface: GameColors.surface,
    ),
    textTheme: TextTheme(
      displayLarge: GoogleFonts.cinzel(
        color: GameColors.textPrimary,
        fontSize: 32,
        fontWeight: FontWeight.bold,
        letterSpacing: 2,
      ),
      displayMedium: GoogleFonts.cinzel(
        color: GameColors.textPrimary,
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
      ),
      titleLarge: GoogleFonts.cinzel(
        color: GameColors.accent,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
      ),
      bodyLarge: GoogleFonts.inter(color: GameColors.textPrimary, fontSize: 16),
      bodyMedium: GoogleFonts.inter(
        color: GameColors.textSecondary,
        fontSize: 14,
      ),
    ),
    cardTheme: CardThemeData(
      color: GameColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: GameColors.cardBorder, width: 1),
      ),
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: GameColors.primary,
        foregroundColor: GameColors.textPrimary,
        textStyle: GoogleFonts.cinzel(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      ),
    ),
  );
}
