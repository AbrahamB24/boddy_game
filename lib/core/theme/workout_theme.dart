import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class WC {
  static const bg = Color(0xFFF9FAFB); // Hintergrund
  // Karten/Buttons/Header: bewusst DIESELBE Farbe wie der Hintergrund —
  // Flächen heben sich einzig über den geworfenen Schatten ab, nie über
  // eine hellere Füllung. (Ausnahmen: Akzent-Blau, Städtelinien.)
  static const surface = Color(0xFFF9FAFB); // Karten
  static const accent = Color(0xFF018ABE); // Akzent blau
  static const text = Color(0xFF36454F); // Schrift / sonstiges
  static const muted = Color(0xFFA9B6C9); // ausgegraut
  static const border = Color(0xFFD8E2EC); // Rahmen (Ableitung aus muted)
  static const success = Color(0xFF3BAE78); // abgeschlossen
  static const danger = Color(0xFFF44336); // destruktiv (Löschen)

  // Dunkles Ende des Akzent-Gradients (Workout-Tile, WotD-Karte, XP-Badge,
  // Bøddy-Score-Kreis) — EIN Wert statt in jedem Screen neu.
  static const accentDark = Color(0xFF015E82);

  // "Carved groove" — die eingelassene Rille hinter Timern, Fortschrittsbalken
  // und dem Groove-Switch. Off-Palette, aber bewusst EIN geteilter Wert.
  static const groove = Color(0xFFE8ECF0);

  // Warnbanner (z. B. "keine Übungen geladen"): weicher gelber Hinweis. Eigenes
  // Token-Set, weil das Palettenblau hier nicht als Warnung lesbar wäre.
  static const warnBg = Color(0xFFFFF3CD);
  static const warnBorder = Color(0xFFFFD700);
  static const warnText = Color(0xFF856404);

  // ── Type scale ────────────────────────────────────────────
  // Five shared text sizes so screens stop inventing 11/13/15/17/… for the
  // same kind of text. Anything bigger (timers, score circles, hero numbers)
  // stays a tuned literal — those are display graphics, not part of the scale.
  static const double fsCaption = 12; // eyebrows, metadata, tiny labels
  static const double fsBody = 14; // default body & list-row text
  static const double fsTitle = 16; // card / list-item titles
  static const double fsSection = 20; // in-page section headers, big counters
  static const double fsScreen = 24; // screen titles

  // Single shared corner radius for every rounded surface (cards, panels,
  // dialogs, tiles, badges, primary buttons) so nothing invents its own.
  // Circles, pills/chips and progress-bar tracks are intentionally excluded.
  static const double radius = 14;

  // Secondary radius for SMALL standalone elements — quick-pick tiles, image
  // thumbnails, search/number inputs, letter badges — that read too round at
  // the full 14. One shared value so small elements don't each pick 8/10/12.
  static const double radiusSmall = 10;

  // Bottom sheets deliberately use a larger top radius than cards; one shared
  // value so every sheet matches.
  static const double sheetRadius = 24;

  // Single shared "floating" shadow — every tappable button/card in the
  // workout feature uses this so they all read as the same elevation
  // language instead of each screen inventing its own.
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: text.withValues(alpha: 0.36),
      blurRadius: 52,
      spreadRadius: -8,
      offset: const Offset(8, 20),
    ),
    BoxShadow(
      color: text.withValues(alpha: 0.20),
      blurRadius: 12,
      offset: const Offset(4, 5),
    ),
  ];

  // Straight-up drop shadow for the bottom nav bar so it floats above the
  // page content. Works as a plain BoxShadow because the Scaffold paints the
  // bar AFTER the body; an in-Column header can't use this (its content
  // sibling paints later and covers the shadow) — see the header scrim in
  // the workout selection screen for that case.
  static List<BoxShadow> get barShadowUp => [
    BoxShadow(
      color: text.withValues(alpha: 0.16),
      blurRadius: 18,
      offset: const Offset(0, -6),
    ),
  ];
}

ThemeData buildWorkoutTheme() {
  return ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: WC.bg,
    // No tap overlay anywhere: buttons/tiles/nav items react via their own
    // color/shadow swaps, never a Material ripple or press highlight. Kills the
    // splash, the press highlight and the hover tint for every InkWell and
    // button in the app (ElevatedButton overlay handled in its theme below).
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    colorScheme: const ColorScheme.light(
      primary: WC.accent,
      secondary: WC.accent,
      surface: WC.surface,
    ),
    textTheme: TextTheme(
      displayLarge: GoogleFonts.outfit(
        color: WC.text,
        fontSize: 32,
        fontWeight: FontWeight.bold,
      ),
      displayMedium: GoogleFonts.outfit(
        color: WC.text,
        fontSize: 24,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: GoogleFonts.outfit(
        color: WC.text,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: GoogleFonts.outfit(
        color: WC.text,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: GoogleFonts.outfit(color: WC.text, fontSize: 16),
      bodyMedium: GoogleFonts.outfit(color: WC.muted, fontSize: 14),
    ),
    cardTheme: CardThemeData(
      color: WC.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WC.radius),
      ),
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: WC.accent,
        foregroundColor: Colors.white,
        overlayColor: Colors.transparent, // no press/hover tint
        textStyle: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WC.radius),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      ),
    ),
    // TextButton / IconButton keep their own press-tint (overlayColor) that
    // ignores the global splash colors above — zero it out so they, too, have
    // no click overlay.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(overlayColor: Colors.transparent),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(overlayColor: Colors.transparent),
    ),
    dividerTheme: const DividerThemeData(color: WC.border, thickness: 1),
  );
}
