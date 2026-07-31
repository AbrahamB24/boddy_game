import 'package:flutter/material.dart';

import '../../features/settlement/widgets/scroll_paper.dart'
    show
        kActionGreen,
        kPageShadow,
        kParchmentDeep,
        kParchmentInk,
        kParchmentLight,
        kParchmentMid;
import '../../features/common/widgets/parchment_page.dart';
import 'foe_theme.dart';

/// THE APP'S ONE THEME (user 2026-07-27: "dieser look gefällt mir, übertrage
/// dies bitte auf die gesamte app … D.h Buttons, Dropdown menüs etc. ebenfalls
/// anpassen").
///
/// Every page is a sheet of parchment now, but the MATERIAL widgets on top of
/// them were still dressed for the dark theme the app started as: a
/// `brightness: dark` ThemeData seeded off gold. That is what made a dropdown
/// open as a near-black card on a cream page, a dialog arrive charcoal, a
/// TextField draw a white cursor on paper, and every unstyled button come out
/// in Material's own purple-ish default.
///
/// Fixing those one call site at a time would be dozens of edits and would miss
/// the next widget somebody adds. A theme is the one place that reaches all of
/// them, including the screens nobody has restyled yet.
///
/// The palette is the paper's own: [kParchmentInk] for anything written,
/// [kParchmentLight] for surfaces that sit ON the page (menus, dialogs), the
/// amber for accents and [kActionGreen] for the commit buttons — the same green
/// `parchmentButton` paints.
///
/// Every one of those names is a ROLE, which is why the app going dark on
/// 2026-07-31 needed no edit here beyond the brightness flags: "the ink" became
/// cream and "the page" became graphite in one place (scroll_paper.dart), and
/// this theme kept asking for the same things.
ThemeData buildParchmentTheme() {
  const ink = kParchmentInk;
  final inkSoft = ink.withValues(alpha: 0.72);
  final inkFaint = ink.withValues(alpha: 0.45);
  const accent = FoE.gold;

  // A field is a facet too (2026-07-31, low poly). OutlineInputBorder cannot
  // bevel, so its corners are taken right down instead — a 10-px round next to a
  // cut card is the one shape that would give the whole thing away.
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(2),
    borderSide: BorderSide(color: c, width: w),
  );

  return ThemeData(
    // DARK again (user 2026-07-31: "setzte das ganze app in den darkmode").
    //
    // This flag is not decoration: it decides every Material default the theme
    // does not name — cursor colours, icon tints, the fallback text colour, the
    // scrollbar, the ripple. Leaving it `light` while the palette went dark is
    // exactly how you end up with a black caret on a graphite field.
    brightness: Brightness.dark,
    scaffoldBackgroundColor: kParchmentMid,
    colorScheme: ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
      surface: kParchmentLight,
      onSurface: ink,
      primary: accent,
      onPrimary: kParchmentLight,
      secondary: kActionGreen,
      onSecondary: kParchmentLight,
      error: FoE.danger,
    ),
    // Phone game: no mouse, so nothing may depend on hover, and every
    // ripple/overscroll should feel like a touch surface.
    splashFactory: InkSparkle.splashFactory,
    splashColor: ink.withValues(alpha: 0.10),
    highlightColor: ink.withValues(alpha: 0.06),
    dividerColor: ink.withValues(alpha: 0.18),
    iconTheme: const IconThemeData(color: ink),

    // Written matter, in the game's one geometric sans.
    textTheme: TextTheme(
      titleLarge: FoE.title(size: 18).copyWith(color: ink),
      titleMedium: FoE.title(size: 14).copyWith(color: ink),
      bodyLarge: FoE.label(size: 13).copyWith(color: ink),
      bodyMedium: FoE.label(size: 12).copyWith(color: ink),
      bodySmall: FoE.dim(size: 11).copyWith(color: inkSoft),
      labelLarge: FoE.label(size: 13).copyWith(color: ink),
    ),

    // ── Surfaces that sit ON the page ──────────────────────────────────────
    // A menu, a dialog and a card are all bits of lighter paper laid on the
    // sheet, with the ink hairline the rest of the app draws its cards with.
    cardTheme: CardThemeData(
      color: kParchmentLight,
      elevation: 2,
      shadowColor: ink.withValues(alpha: 0.35),
      shape: FoE.facet(radius: 12, side: BorderSide(color: ink.withValues(alpha: 0.18))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: kParchmentLight,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: FoE.title(size: 15).copyWith(color: ink),
      contentTextStyle: FoE.label(size: 13).copyWith(color: inkSoft),
      shape: FoE.facet(radius: 14, side: BorderSide(color: ink.withValues(alpha: 0.22))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: kParchmentLight,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      textStyle: FoE.label(size: 12).copyWith(color: ink),
      shape: FoE.facet(radius: 12, side: BorderSide(color: ink.withValues(alpha: 0.22))),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(kParchmentLight),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          FoE.facet(radius: 12, side: BorderSide(color: ink.withValues(alpha: 0.22))),
        ),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: FoE.label(size: 12).copyWith(color: ink),
      menuStyle: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(kParchmentLight),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: kParchmentDeep,
      contentTextStyle: FoE.label(size: 13).copyWith(color: ink),
      behavior: SnackBarBehavior.floating,
      shape: FoE.facet(radius: 12, side: BorderSide(color: ink.withValues(alpha: 0.25))),
    ),

    // ── Bars ───────────────────────────────────────────────────────────────
    // The dev forms still use a real AppBar; give it the same band the
    // ParchmentHeader paints so they match without being rewritten.
    // ── The MATERIAL app bar, dressed as the app's own band ──
    // User 2026-07-31: "überall wo es einen header hat, soll dieser immer genau
    // gleich aussehen". The screens that matter wear [ParchmentHeader]; Dev Mode
    // uses plain Scaffold AppBars, and rewriting a dozen dev forms to carry the
    // band widget would be a dozen edits and a thirteenth the day someone adds a
    // form. Dressing the THEME reaches all of them at once — same fill, same
    // title style, same engraved ink, same cast.
    appBarTheme: AppBarTheme(
      backgroundColor: ParchmentHeader.bandFill,
      surfaceTintColor: Colors.transparent,
      foregroundColor: ParchmentHeader.engravedInk,
      elevation: 4,
      shadowColor: kPageShadow.withValues(alpha: 0.34),
      centerTitle: false,
      titleTextStyle: ParchmentHeader.titleStyle(),
      iconTheme: IconThemeData(color: ParchmentHeader.engravedInk),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: accent,
      unselectedLabelColor: inkFaint,
      labelStyle: FoE.label(size: 12).copyWith(color: accent),
      unselectedLabelStyle: FoE.label(size: 12),
      indicatorColor: accent,
      dividerColor: ink.withValues(alpha: 0.15),
    ),

    // ── Controls ───────────────────────────────────────────────────────────
    // The commit green every hand-built button already wears, so an unstyled
    // ElevatedButton lands in the same family instead of Material's default.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kActionGreen,
        foregroundColor: kParchmentLight,
        disabledBackgroundColor: ink.withValues(alpha: 0.10),
        disabledForegroundColor: inkFaint,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: FoE.label(size: 13),
        shape: FoE.facet(radius: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: FoE.label(size: 13),
        shape: FoE.facet(radius: 10),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        side: BorderSide(color: accent.withValues(alpha: 0.55)),
        textStyle: FoE.label(size: 13),
        shape: FoE.facet(radius: 12),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kActionGreen,
      foregroundColor: kParchmentLight,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        foregroundColor: inkSoft,
        selectedForegroundColor: accent,
        selectedBackgroundColor: accent.withValues(alpha: 0.16),
        side: BorderSide(color: ink.withValues(alpha: 0.30)),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? accent
            : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(kParchmentLight),
      side: BorderSide(color: ink.withValues(alpha: 0.45)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? accent : inkFaint,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? accent.withValues(alpha: 0.35)
            : ink.withValues(alpha: 0.12),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: accent,
      inactiveTrackColor: ink.withValues(alpha: 0.13),
      thumbColor: accent,
      overlayColor: accent.withValues(alpha: 0.12),
      trackHeight: 6,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: accent,
      linearTrackColor: ink.withValues(alpha: 0.13),
      circularTrackColor: ink.withValues(alpha: 0.13),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: ink.withValues(alpha: 0.06),
      selectedColor: accent.withValues(alpha: 0.16),
      labelStyle: FoE.label(size: 11).copyWith(color: ink),
      side: BorderSide(color: ink.withValues(alpha: 0.22)),
      shape: FoE.facet(radius: 10),
    ),
    listTileTheme: ListTileThemeData(
      textColor: ink,
      iconColor: accent,
      titleTextStyle: FoE.label(size: 13).copyWith(color: ink),
      subtitleTextStyle: FoE.dim(size: 11).copyWith(color: inkSoft),
    ),

    // ── Typing on paper ────────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ink.withValues(alpha: 0.05),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      labelStyle: FoE.dim(size: 12).copyWith(color: inkSoft),
      hintStyle: FoE.dim(size: 12).copyWith(color: inkFaint),
      enabledBorder: border(ink.withValues(alpha: 0.22)),
      border: border(ink.withValues(alpha: 0.22)),
      focusedBorder: border(accent, 1.4),
      errorBorder: border(FoE.danger),
      focusedErrorBorder: border(FoE.danger, 1.4),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: accent,
      selectionColor: accent.withValues(alpha: 0.25),
      selectionHandleColor: accent,
    ),
  );
}
