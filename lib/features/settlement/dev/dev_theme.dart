import 'package:flutter/material.dart';

import '../../../core/theme/cream_kit.dart';
import '../../../core/ui/pressable.dart';
import '../../creatures/models/species_def.dart' show kSpeciesDefs;
import 'dev_foe.dart';
import '../../../core/theme/voxel_kit.dart' show vr;

/// The dev forms' Material theme: cream (user 2026-09-20, "Dev Mode Variante 3").
///
/// The forms are plain Material — TextFormField, DropdownButtonFormField,
/// Checkbox, TabBar — so they take their look from the ambient theme. It is the
/// Holz kit's: paper ground, ink text, sand fields with a tan hairline and a gold
/// ring on focus, gold for what commits. Every dev screen wraps its Scaffold in
/// `Theme(data: buildDevModeTheme(), child: ...)`.
ThemeData buildDevModeTheme() {
  const ink = kBoxInk;
  final inkSoft = ink.withValues(alpha: 0.72);
  final inkFaint = ink.withValues(alpha: 0.45);
  final line = CreamPalette.tan.withValues(alpha: 0.55);

  OutlineInputBorder border(Color c, [double w = 1.5]) => OutlineInputBorder(
    borderRadius: vr(10),
    borderSide: BorderSide(color: c, width: w),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: CreamPalette.paperTop,
    canvasColor: CreamPalette.paperTop,
    colorScheme: ColorScheme.fromSeed(
      seedColor: CreamPalette.gold,
      brightness: Brightness.light,
      primary: CreamPalette.goldDeep,
      onPrimary: ink,
      secondary: CreamPalette.accent,
      surface: CreamPalette.paperTop,
      onSurface: ink,
      error: CreamPalette.warn,
    ),
    textTheme: ThemeData.light().textTheme.apply(
      bodyColor: ink,
      displayColor: ink,
    ),
    iconTheme: const IconThemeData(color: ink),
    dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(color: ink),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: ink,
      unselectedLabelColor: inkSoft,
      indicatorColor: CreamPalette.goldDeep,
      dividerColor: line,
      labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
      unselectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.55),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      labelStyle: TextStyle(color: inkSoft, fontSize: 12),
      floatingLabelStyle: const TextStyle(
        color: CreamPalette.accent,
        fontWeight: FontWeight.w700,
      ),
      hintStyle: TextStyle(color: inkFaint),
      helperStyle: TextStyle(color: inkSoft, fontSize: 11),
      errorStyle: const TextStyle(color: CreamPalette.warn, fontSize: 11),
      border: border(line),
      enabledBorder: border(line),
      focusedBorder: border(CreamPalette.gold, 2),
      errorBorder: border(CreamPalette.warn),
      focusedErrorBorder: border(CreamPalette.warn, 2),
      disabledBorder: border(line.withValues(alpha: 0.25)),
    ),
    dropdownMenuTheme: const DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(CreamPalette.paperBottom),
      ),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: CreamPalette.paperBottom,
      textStyle: TextStyle(color: ink, fontWeight: FontWeight.w600),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: CreamPalette.paperTop,
      titleTextStyle: const TextStyle(
        color: ink,
        fontSize: 17,
        fontWeight: FontWeight.w800,
      ),
      contentTextStyle: TextStyle(color: inkSoft, fontSize: 13, height: 1.4),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? CreamPalette.gold
            : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(ink),
      side: BorderSide(color: CreamPalette.tan, width: 1.5),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(CreamPalette.tileTop),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? CreamPalette.gold
            : CreamPalette.tan.withValues(alpha: 0.35),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: CreamPalette.gold,
      inactiveTrackColor: CreamPalette.tan.withValues(alpha: 0.3),
      thumbColor: CreamPalette.goldDeep,
      overlayColor: CreamPalette.gold.withValues(alpha: 0.2),
      valueIndicatorColor: CreamPalette.accent,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: CreamPalette.paperBottom,
      selectedColor: CreamPalette.gold,
      labelStyle: const TextStyle(color: ink, fontWeight: FontWeight.w700),
      side: BorderSide(color: line),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: CreamPalette.accent,
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: CreamPalette.gold,
        foregroundColor: ink,
        elevation: 0,
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: vr(12)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: CreamPalette.ink,
      contentTextStyle: TextStyle(color: CreamPalette.paperTop),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: CreamPalette.goldDeep,
    ),
  );
}

/// The confirm dialog before a delete: a cream card, Cancel and a warn-coloured
/// Delete. A plain Dialog rather than Material's AlertDialog, so it reads the
/// same whichever theme sits above the Navigator.
Future<bool> confirmDeleteDialog(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: creamCard(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: FoE.title(size: 15)),
              const SizedBox(height: 8),
              Text(
                message,
                style: FoE.label(size: 13).copyWith(color: FoE.textDim),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Pressable(
                    onTap: () => Navigator.pop(context, false),
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      alignment: Alignment.center,
                      decoration: raisedTile(radius: 12),
                      child: Text('Cancel', style: FoE.label(size: 12)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Pressable(
                    onTap: () => Navigator.pop(context, true),
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: CreamPalette.warn,
                        borderRadius: vr(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0xFF7D3512),
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        'Delete',
                        style: FoE.label(size: 12).copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return ok ?? false;
}

/// A monster's name in ITS RARITY'S colour (user 2026-07-30: "Gib mir zudem im
/// ganzen Kampagnen dev screen an, welche Seltenheit ein Monster hat, indem der
/// Name in der Schriftfarbe gehalten ist").
///
/// The campaign screens list species by name over and over — in a node's enemy
/// rows, in the per-era distribution, in the roster the dice draws from — and a
/// name alone says nothing about what you are actually putting in front of the
/// player. The rarity already owns a colour ([CreatureRarity.color]); this is
/// simply that colour, applied where the name is read.
///
/// Falls back to the ink for an id nothing defines, so a stale reference still
/// reads as text rather than disappearing.
Color speciesNameColor(String speciesId) =>
    kSpeciesDefs[speciesId]?.rarity.color ?? FoE.parchment;
