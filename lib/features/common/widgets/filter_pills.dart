import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../../settlement/widgets/scroll_paper.dart'
    show kParchmentInk, kParchmentLight;

/// ONE LOOK FOR EVERY SEARCH / FILTER / SORT CONTROL (user 2026-07-27: "alle
/// filter und sortierfunktionien sollen so aussehen wie bei den eggs").
///
/// Each control is a ROUNDED PILL that states its current value IN WORDS, and
/// an ENGAGED pill wears the accent. That is the whole idea: a row of pills
/// says what it is doing at a glance, where the shapes it replaces — captioned
/// Material dropdowns on one screen, bare icon squares on another — made you
/// open them to find out whether anything was filtered at all.
///
/// The palette is a parameter, not a constant: these sit on parchment pages
/// (the egg picker, breeding) and on the dark ones (Monsters). Same pill, same
/// behaviour, the surface it is standing on.
class PillPalette {
  final Color ink;
  final Color inkFaint;
  final Color accent;
  final Color fill;
  final Color border;

  /// The popup menu's own surface.
  final Color menuSurface;

  const PillPalette({
    required this.ink,
    required this.inkFaint,
    required this.accent,
    required this.fill,
    required this.border,
    required this.menuSurface,
  });

  /// THE pill palette — ink on the page, whatever the page is made of.
  ///
  /// It is built from the page's own tones ([kParchmentInk] and friends), so it
  /// followed the app into dark mode on 2026-07-31 without an edit: the "ink" is
  /// what you write on this stock with, and the fill is that ink at 6 % — a wash
  /// of the writing colour over the page, which is a recess on paper and a
  /// raised tint on graphite. Both read as "a control sits here".
  ///
  /// The ACCENT is the one thing that could not be derived: it used to be a
  /// literal burnt amber picked to read on cream, and burnt amber on graphite is
  /// mud. It now points at the theme's own accent.
  static final PillPalette parchment = PillPalette(
    ink: kParchmentInk,
    inkFaint: kParchmentInk.withValues(alpha: 0.55),
    accent: FoE.goldBright,
    fill: kParchmentInk.withValues(alpha: 0.06),
    border: kParchmentInk.withValues(alpha: 0.22),
    menuSurface: kParchmentLight,
  );

  /// One pill's surface. ENGAGED — something typed, something filtered, a
  /// non-default order — is the accent; idle is the plain recess.
  ShapeDecoration skin(bool engaged) => ShapeDecoration(color: engaged ? accent.withValues(alpha: 0.14) : fill, shape: FoE.facet(radius: 19, side: BorderSide(color: engaged ? accent : border,
      width: engaged ? 1.4 : 1)));
}

/// The height every pill shares, so a row of them lines up.
const double kPillHeight = 38;

/// A lens, what you typed, and a ✕ once there is something to clear.
class SearchPill extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final PillPalette palette;
  final String hint;

  const SearchPill({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.palette,
    this.hint = 'Search by name',
  });

  @override
  Widget build(BuildContext context) {
    final engaged = controller.text.isNotEmpty;
    return Container(
      height: kPillHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: palette.skin(engaged),
      child: Row(
        children: [
          Icon(
            Icons.search,
            size: 16,
            color: engaged ? palette.accent : palette.inkFaint,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: FoE.label(size: 12).copyWith(color: palette.ink),
              cursorColor: palette.accent,
              decoration: InputDecoration(
                isDense: true,
                // NO SKIN OF ITS OWN (user 2026-07-27: "der innere Kreis
                // löschen"). The pill IS the field's container — its outline,
                // its fill, its radius. Since the app theme grew an
                // inputDecorationTheme (filled + a rounded border), a bare
                // `border: InputBorder.none` stopped being enough: `border` is
                // only the FALLBACK for the states, so the theme's
                // enabledBorder went on drawing a second rounded box inside the
                // pill. Every state has to be silenced by name.
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: hint,
                hintStyle: FoE.dim(size: 12).copyWith(color: palette.inkFaint),
              ),
            ),
          ),
          if (engaged)
            GestureDetector(
              onTap: () {
                controller.clear();
                onChanged('');
              },
              child: Icon(Icons.close, size: 16, color: palette.accent),
            ),
        ],
      ),
    );
  }
}

/// A pill that opens a menu. [entries] are value → label, in order.
///
/// A NULL VALUE IS NOT USABLE HERE: PopupMenuButton reads a null result as a
/// dismissed menu, so an "All"/"Total" entry has to carry a sentinel — pass
/// `''` for it and map back in [onSelected]. Every caller does this the same
/// way; the alternative is an entry that silently never fires.
class MenuPill<T> extends StatelessWidget {
  final IconData icon;

  /// What the control is currently set to, in words. Not the field's NAME —
  /// "All monsters" and "Total power" say more than "Filter" and "Sort".
  final String label;

  final bool engaged;
  final T value;
  final List<MapEntry<T, String>> entries;
  final ValueChanged<T> onSelected;
  final PillPalette palette;

  /// Replaces the ▾ on the pill — the sort control puts its direction arrow
  /// here.
  final Widget? trailing;

  /// Drawn on the CURRENT entry inside the menu instead of a ✓. The sort
  /// control repeats its arrow there, so tapping the current field again reads
  /// as "flip", not as "nothing happened".
  final String? selectedTrailing;

  const MenuPill({
    super.key,
    required this.icon,
    required this.label,
    required this.engaged,
    required this.value,
    required this.entries,
    required this.onSelected,
    required this.palette,
    this.trailing,
    this.selectedTrailing,
  });

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
    tooltip: '',
    color: palette.menuSurface,
    elevation: 10,
    position: PopupMenuPosition.under,
    padding: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: palette.border),
    ),
    onSelected: onSelected,
    itemBuilder: (_) => [
      for (final e in entries)
        PopupMenuItem<T>(
          value: e.key,
          height: 40,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  e.value,
                  style: FoE.label(size: 12).copyWith(
                    color: e.key == value ? palette.accent : palette.ink,
                  ),
                ),
              ),
              if (e.key == value)
                Text(
                  selectedTrailing ?? '✓',
                  style: FoE.value(size: 13).copyWith(color: palette.accent),
                ),
            ],
          ),
        ),
    ],
    child: Container(
      height: kPillHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: palette.skin(engaged),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: engaged ? palette.accent : palette.inkFaint,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FoE.label(size: 12).copyWith(color: palette.ink),
            ),
          ),
          trailing ??
              Icon(Icons.expand_more, size: 16, color: palette.inkFaint),
        ],
      ),
    ),
  );
}

/// A pill that just gets TAPPED — no menu of its own. The Monsters screen's
/// multi-select filter opens a custom overlay that a PopupMenu cannot express
/// (several elements and rarities at once), so its pill only has to look and
/// report like the others.
class ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool engaged;
  final VoidCallback onTap;
  final PillPalette palette;

  const ActionPill({
    super.key,
    required this.icon,
    required this.label,
    required this.engaged,
    required this.onTap,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      height: kPillHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: palette.skin(engaged),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: engaged ? palette.accent : palette.inkFaint,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FoE.label(size: 12).copyWith(color: palette.ink),
            ),
          ),
          Icon(Icons.expand_more, size: 16, color: palette.inkFaint),
        ],
      ),
    ),
  );
}
