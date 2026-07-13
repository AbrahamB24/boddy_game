import 'package:flutter/material.dart';
import '../../../core/theme/foe_theme.dart';

// The app's ambient Material theme (buildWorkoutTheme in workout_theme.dart)
// is a LIGHT theme built for the Workout side of the app. Dev Mode's plain
// TextFormField/DropdownButtonFormField/Checkbox widgets would otherwise
// inherit that theme's colors — near-invisible against FoE's near-black
// background, which is why the original Dev Mode UI was hard to read. Every
// Dev Mode screen wraps its Scaffold in `Theme(data: buildDevModeTheme(),
// child: ...)` so form fields are readable without repeating color
// overrides on every single field.
ThemeData buildDevModeTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: FoE.bg,
    colorScheme: const ColorScheme.dark(
      primary: FoE.gold,
      secondary: FoE.gold,
      surface: FoE.panelDark,
      onSurface: FoE.parchment,
      error: Colors.redAccent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: FoE.panelDark,
      labelStyle: FoE.label(size: 13).copyWith(color: FoE.gold),
      floatingLabelStyle: FoE.label(size: 13).copyWith(color: FoE.goldBright),
      hintStyle: FoE.label(size: 13).copyWith(color: FoE.textDim),
      helperStyle: FoE.label(size: 11).copyWith(color: FoE.textDim),
      border: const OutlineInputBorder(
        borderSide: BorderSide(color: FoE.border),
      ),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: FoE.border),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: FoE.goldBright, width: 2),
      ),
      disabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: FoE.textMuted),
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: FoE.goldBright,
      selectionColor: FoE.borderGold,
      selectionHandleColor: FoE.goldBright,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? FoE.gold : FoE.panelMid,
      ),
      checkColor: const WidgetStatePropertyAll(Colors.black),
      side: const BorderSide(color: FoE.border, width: 1.5),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: FoE.panelMid,
      selectedColor: FoE.gold,
      labelStyle: FoE.label(size: 12),
      secondaryLabelStyle: FoE.label(size: 12).copyWith(color: Colors.black),
      side: const BorderSide(color: FoE.border),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: FoE.panelDark,
      titleTextStyle: FoE.title(size: 16),
      iconTheme: const IconThemeData(color: FoE.gold),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: FoE.goldBright,
      unselectedLabelColor: FoE.textDim,
      indicatorColor: FoE.gold,
      labelStyle: FoE.label(size: 13),
    ),
    iconTheme: const IconThemeData(color: FoE.parchment),
    dropdownMenuTheme: DropdownMenuThemeData(textStyle: FoE.label(size: 13)),
    popupMenuTheme: PopupMenuThemeData(
      color: FoE.panelDark,
      textStyle: FoE.label(size: 13),
    ),
    textTheme: TextTheme(
      bodyLarge: FoE.label(size: 14),
      bodyMedium: FoE.label(size: 13),
      bodySmall: FoE.label(size: 12),
    ),
  );
}

// Matches the FoE-styled confirm dialog already used in
// settlement_screen.dart's _confirmReset — a plain Dialog + FoE.panel()
// Container, not Material's AlertDialog, so it reads correctly regardless
// of ambient theme (a showDialog route sits above the Navigator and does
// NOT automatically inherit a Theme wrapped only around a lower Scaffold).
Future<bool> confirmDeleteDialog(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 280,
        decoration: FoE.panel(radius: 12),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: FoE.title(size: 15)),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: FoE.label(size: 13).copyWith(color: FoE.parchment),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context, false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: FoE.btn(),
                    child: Text(
                      'Cancel',
                      style: FoE.label(size: 13).copyWith(color: FoE.parchment),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context, true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade900.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.red.shade700),
                    ),
                    child: Text(
                      'Delete',
                      style: FoE.label(
                        size: 13,
                      ).copyWith(color: Colors.red.shade300),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return ok ?? false;
}
