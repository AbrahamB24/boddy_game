import 'package:flutter/material.dart';
import '../../creatures/models/species_def.dart' show kSpeciesDefs;
import '../../../core/theme/foe_theme.dart';
import '../../../core/theme/parchment_theme.dart';

// Dev Mode's plain TextFormField/DropdownButtonFormField/Checkbox widgets
// inherit the ambient Material theme's colors, which can render
// near-invisible against FoE's near-black background — which is why the
// original Dev Mode UI was hard to read. Every
// Dev Mode screen wraps its Scaffold in `Theme(data: buildDevModeTheme(),
// child: ...)` so form fields are readable without repeating color
// overrides on every single field.
/// The dev forms' theme (user 2026-07-27: "übertrage dies bitte auf die gesamte
/// app … D.h Buttons, Dropdown menüs etc. ebenfalls anpassen").
///
/// It used to be a whole second ThemeData — `Brightness.dark`, a dark colour
/// scheme, its own field borders, chips, app bar and popup menus. That was
/// right when the app was dark chrome and the forms needed readable fields on
/// it; now it is the one thing left holding a dark surface on a parchment app,
/// and every value in it is a value the app theme already carries.
///
/// So it IS the app theme. The wrapper stays because the forms all call it —
/// deleting it would be a change to fifteen files for no behaviour — and
/// because dev forms may yet want a tweak of their own; there is now exactly
/// one place to put it.
ThemeData buildDevModeTheme() => buildParchmentTheme();

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
/// Falls back to the parchment ink for an id nothing defines, so a stale
/// reference still reads as text rather than disappearing.
Color speciesNameColor(String speciesId) =>
    kSpeciesDefs[speciesId]?.rarity.color ?? FoE.parchment;
