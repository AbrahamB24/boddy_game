import 'package:flutter/material.dart';

import '../../features/settlement/widgets/scroll_paper.dart'
    show kActionGreen, kPageShadow, kParchmentInk, kParchmentLight;
import '../../features/common/widgets/parchment_page.dart';
import 'cream_kit.dart' show CreamPalette, kBoxInk, kBoxInkSoft;
import 'foe_theme.dart';
import 'strategy_theme.dart';
import 'voxel_kit.dart';

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
/// A button overlay for a touch screen: a tint while PRESSED, nothing for hover
/// or focus (a phone has neither, and a browser test session must not show one).
WidgetStateProperty<Color?> touchOnly(Color base) =>
    WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.pressed)
          ? base.withValues(alpha: 0.14)
          : Colors.transparent,
    );

ThemeData buildParchmentTheme() {
  const ink = kParchmentInk;
  final inkSoft = ink.withValues(alpha: 0.72);
  final inkFaint = ink.withValues(alpha: 0.45);
  const accent = FoE.gold;

  // A field is a facet too (2026-07-31, low poly). OutlineInputBorder cannot
  // bevel, so its corners are taken right down instead — a 10-px round next to a
  // cut card is the one shape that would give the whole thing away.
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: vr(2),
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
    // The pixel face for every Text that names no family of its own.
    fontFamily: Voxel.font,
    // The wood ground, not the old navy page (user 2026-09-20: "der blaue
    // Hintergrund ist oft noch zu sehen und schimmert durch") — whatever a
    // screen leaves uncovered (edges, a transition, a translucent layer) now
    // shows the same ground the kit's menus stand on.
    scaffoldBackgroundColor: CreamPalette.groundBottom,
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
    // NO hover or focus tint anywhere (user 2026-09-28: "Hovereffekte braucht es
    // nicht, da es für Smartphones programmiert wird"). InkWell reads these two;
    // the Material buttons below carry the same rule in their own overlay.
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
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
      shape: FoE.facet(
        radius: 12,
        side: BorderSide(color: ink.withValues(alpha: 0.18)),
      ),
    ),
    // Modal surfaces wear the building dialog's template (user 2026-09-18): the
    // cream card, navy ink — even though the app's own text theme is light, a
    // dialog, a menu or a dropdown is a piece of CREAM laid on the screen.
    dialogTheme: DialogThemeData(
      backgroundColor: Strategy.cream,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: FoE.title(size: 15).copyWith(color: kBoxInk),
      contentTextStyle: FoE.label(size: 13).copyWith(color: kBoxInkSoft),
      shape: const VoxelShape(notch: 3),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Strategy.cream,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      textStyle: FoE.label(size: 12).copyWith(color: kBoxInk),
      shape: const VoxelShape(notch: 2),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Strategy.cream),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          const VoxelShape(notch: 2),
        ),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: FoE.label(size: 12).copyWith(color: kBoxInk),
      menuStyle: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Strategy.cream),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      // A bottom sheet spans the whole (long) landscape width otherwise; cap it to
      // a readable column, centred (2026-09-18).
      constraints: BoxConstraints(maxWidth: 720),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Strategy.cream,
      contentTextStyle: FoE.label(size: 13).copyWith(color: kBoxInk),
      behavior: SnackBarBehavior.floating,
      shape: FoE.facet(
        radius: 12,
        side: BorderSide(color: ink.withValues(alpha: 0.25)),
      ),
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
      // NO automatic full-width divider (user 2026-08-31: "alle weissen
      // Trennstriche sollen nicht über die ganze Breite gehen, da sie sonst
      // mit dem Mäanderband kollidieren") — a TabBar sitting directly in a
      // ParchmentPage body (e.g. Management) has no margin of its own, so
      // this ran edge to edge, straight through the bands on both sides.
      // Screens that want a divider under their TabBar draw their own,
      // inset to [ParchmentPage.kParchmentPagePad] like the rest of the
      // page's content.
      dividerColor: Colors.transparent,
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
      ).copyWith(overlayColor: touchOnly(kParchmentLight)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: FoE.label(size: 13),
        shape: FoE.facet(radius: 10),
      ).copyWith(overlayColor: touchOnly(accent)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        side: BorderSide(color: accent.withValues(alpha: 0.55)),
        textStyle: FoE.label(size: 13),
        shape: FoE.facet(radius: 12),
      ).copyWith(overlayColor: touchOnly(accent)),
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
        (s) => s.contains(WidgetState.selected) ? accent : Colors.transparent,
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
