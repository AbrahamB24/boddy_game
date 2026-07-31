import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../../common/widgets/parchment_page.dart';
import 'scroll_paper.dart';

/// One button on the [QuickPad].
class QuickPadItem {
  /// Use a FILLED glyph (user 2026-07-29: "Fülle die Icons jeweils aus"). With
  /// the labels gone the glyph is the entire button, and an outline one reads
  /// as a hole in the key rather than a thing stamped on it.
  final IconData icon;

  /// NOT drawn — the tile is icon-only now. It stays as the button's
  /// accessible name, so a screen reader still says "Build" rather than
  /// announcing an unlabelled button.
  final String label;

  final VoidCallback onTap;

  /// Drawn as a badge on the tile's corner when > 0 — unread events, claimable
  /// tasks, items in the bag.
  final int badge;

  /// Highlights the tile in the accent green. For the destination you are
  /// already looking at, or a state the player has to come back to.
  final bool active;

  const QuickPadItem(
    this.icon,
    this.label,
    this.onTap, {
    this.badge = 0,
    this.active = false,
  });
}

/// THE SETTLEMENT'S CONTROLS, AS LOOSE BUTTONS IN THE CORNER (user 2026-07-29:
/// "bag, notification und tägliche ziele sind zusammen mit den Buttons build,
/// map, trips, monster und manage einzelne Buttons ohne Footer unten rechts").
///
/// It replaces a full-width nav bar, and that is the point: the bar was a solid
/// plank across the bottom of a map you are supposed to be looking at, and it
/// was only ever the five destinations — the bag, the daily tasks and the bell
/// were exiled to the top-right corner, as far from the thumb as a phone can
/// put them, purely because that is where there was room.
///
/// Now all eight are the same kind of object in one place: separate tiles,
/// floating over the map, in the bottom-right corner where a thumb rests. The
/// map runs under and around them.
///
/// LAID OUT FROM THE CORNER OUT: the list's first item lands bottom-right, and
/// the rest fill leftwards and upwards. So the order a caller passes is the
/// order of reach — put the thing that gets pressed most first.
class QuickPad extends StatelessWidget {
  final List<QuickPadItem> items;

  /// Tiles per row. Two keeps the pad narrow enough that it covers a corner of
  /// the map rather than a band of it.
  final int columns;

  const QuickPad({super.key, required this.items, this.columns = 2});

  static const double _tile = 58;
  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    final rows = <List<QuickPadItem>>[];
    for (var i = 0; i < items.length; i += columns) {
      final end = i + columns;
      rows.add(items.sublist(i, end > items.length ? items.length : end));
    }
    // Built from the corner OUTWARDS, then flipped: rows.first is the bottom
    // row and, within a row, items.first is the rightmost tile.
    final laid = rows.reversed.toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var r = 0; r < laid.length; r++) ...[
            if (r > 0) const SizedBox(height: _gap),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var c = laid[r].length - 1; c >= 0; c--) ...[
                  if (c < laid[r].length - 1) const SizedBox(width: _gap),
                  _QuickTile(item: laid[r][c]),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}


/// ONE TILE, AS A PHYSICAL KEY (user 2026-07-29: "der eckige schatten gefällt
/// mir nicht. Allgemein soll der Button spannender werden, mehr 3d Effekt").
///
/// It was a flat rounded rectangle with a drop shadow, and the shadow came out
/// SQUARE: the decoration was painted by [Ink], which paints into the enclosing
/// Material's ink layer and clips at the widget's own bounds — so the blur was
/// cut off at the box's four straight edges instead of falling away around the
/// corners. Painting the decoration on a plain Container fixes that by itself.
///
/// What makes it read as three-dimensional is the shape underneath, though, not
/// the shadow. The tile is built the way a real key is:
///
///  • a PLINTH — the button's dark side wall, a rounded slab offset down by
///    [_depth], which is the only part of the tile the ambient shadow hangs off;
///  • a FACE on top of it, in the header's band gradient, with the band's lit
///    hairline along its top edge and a soft diagonal sheen over its shoulder;
///  • and a PRESS that drops the face onto the plinth. The travel is the whole
///    depth, so the key visibly bottoms out and the shadow collapses with it.
///
/// A ripple would fight all of that (it spreads flat across a face that is
/// moving), so the press animation IS the feedback and there is no InkWell.
class _QuickTile extends StatefulWidget {
  final QuickPadItem item;

  const _QuickTile({required this.item});

  /// How far the face stands off the plinth — the button's travel.
  static const double depth = 4;

  @override
  State<_QuickTile> createState() => _QuickTileState();
}

class _QuickTileState extends State<_QuickTile> {
  bool _down = false;

  void _setDown(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    const depth = _QuickTile.depth;
    final face = QuickPad._tile;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: item.onTap,
      onTapDown: (_) => _setDown(true),
      onTapUp: (_) => _setDown(false),
      onTapCancel: () => _setDown(false),
      child: SizedBox(
        width: face,
        height: face + depth,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ── The side wall ────────────────────────────────────────────
            // Sits at the bottom of the slot, so the face standing at the top
            // leaves exactly [depth] of it showing as the button's edge. It
            // also carries the shadow: hung off the tile's LOWEST layer, the
            // blur falls away around the rounded corners instead of from under
            // a floating rectangle.
            Positioned(
              left: 0,
              right: 0,
              top: depth,
              height: face,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: item.active
                      ? Color.lerp(FoE.positive, kParchmentInk, 0.55)!
                      : Color.lerp(kParchmentDeep, kParchmentInk, 0.62)!,
                  borderRadius: BorderRadius.circular(_radius),
                  boxShadow: [
                    // Two shadows, because one cannot do both jobs: a tight
                    // dark one says the key TOUCHES the map, a wide soft one
                    // says it stands above it. Both shrink when it is pressed.
                    BoxShadow(
                      color: kPageShadow.withValues(alpha: _down ? 0.30 : 0.38),
                      blurRadius: _down ? 3 : 5,
                      spreadRadius: -2,
                      offset: Offset(0, _down ? 1 : 2),
                    ),
                    BoxShadow(
                      color: kPageShadow.withValues(alpha: _down ? 0.14 : 0.22),
                      blurRadius: _down ? 8 : 14,
                      spreadRadius: -3,
                      offset: Offset(0, _down ? 3 : 7),
                    ),
                  ],
                ),
              ),
            ),
            // ── The face ─────────────────────────────────────────────────
            AnimatedPositioned(
              duration: const Duration(milliseconds: 70),
              curve: Curves.easeOut,
              left: 0,
              right: 0,
              top: _down ? depth : 0,
              height: face,
              child: _face(item),
            ),
          ],
        ),
      ),
    );
  }

  static const double _radius = 17;

  /// The colour of the cut itself: the key's own material, taken a shade
  /// darker so the recess has a floor. An ACTIVE key tints it towards the
  /// accent — still a dent, but a green one.
  static Color _dentFloor(QuickPadItem item) => item.active
      ? Color.lerp(ParchmentHeader.engravedInk, FoE.positive, 0.45)!
      : ParchmentHeader.engravedInk;

  /// The glyph, with the two label lines' room added to it.
  static const double _glyph = 34;

  /// How far the punched slug sits below the hole it was pressed out of — the
  /// depth of the stamp. Two pixels, dialled back from three (user 2026-07-29:
  /// "effekt wieder etwas zurückschrauben"): enough that the dark crescent
  /// above it is a shape rather than an artefact, not so much that the glyph
  /// reads as badly centred.
  static const double _punch = 2;


  /// The key's top surface: the header's band, lit hard along its top edge,
  /// with the glyph pressed INTO it.
  Widget _face(QuickPadItem item) => Semantics(
    label: item.label,
    button: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        // The header's band, verbatim — these are the same material as the bar
        // at the top of the screen.
        color: ParchmentHeader.bandFill,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(
          color: item.active ? FoE.positive : ParchmentHeader.bandRule,
          width: item.active ? 1.6 : 1,
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── The highlight, a hairline only (user 2026-07-29: "füge bei den
          //    Buttons noch ein helleres Highlight ein") ──
          // It was a hairline over a GLOSS — a wash across the top half. The
          // gloss went with the header's gradient (user 2026-07-31: "alle
          // header sollen keine Farbverlauf haben"), because a key cut from the
          // band has to be the same material as the band.
          Positioned(
            top: 1.5,
            left: 9,
            right: 9,
            child: Container(
              height: 1.5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.10),
                    Colors.white.withValues(alpha: 0.55),
                    Colors.white.withValues(alpha: 0.10),
                  ],
                ),
              ),
            ),
          ),
          // ── The glyph, CUT INTO THE FACE ────────────────────────────
          // The reference the user sent (2026-07-29) is letterpress, and the
          // thing that makes it work is counter-intuitive: THE GLYPH IS NOT A
          // MARK. It is the same material as the key, only a shade darker for
          // the floor of the dent — no ink at all. Everything you actually see
          // is two hairlines of light:
          //
          //   • a dark one along the TOP, which is the cut wall standing in its
          //     own shadow, and
          //   • a white one along the BOTTOM, which is the far wall catching
          //     the same light the face's gloss comes from.
          //
          // Every earlier attempt here drew a dark, saturated glyph and hung
          // shadows off it — which is a mark PRINTED on the surface with a
          // shadow, however deep the shadow gets, because the shape itself was
          // still a foreign colour sitting on top. Take the colour away and it
          // falls into the key.
          //
          // The whole thing is nudged down by [_punch] as well, so it does not
          // sit on the key's centre line: the plainest possible signal that it
          // is not lying ON the surface.
          Center(
            child: Transform.translate(
              offset: const Offset(0, _punch),
              child: Icon(
                item.icon,
                size: _glyph,
                color: _dentFloor(item),
                shadows: ParchmentHeader.engraved(depth: 1.4),
              ),
            ),
          ),
          if (item.badge > 0)
            Positioned(
              top: -5,
              right: -5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 18),
                decoration: BoxDecoration(
                  color: FoE.danger,
                  borderRadius: BorderRadius.circular(9),
                  // A ring in the TILE's colour, so the badge reads as pinned
                  // on it rather than as part of the map behind.
                  border: Border.all(color: kParchmentDeep, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: kPageShadow.withValues(alpha: 0.35),
                      blurRadius: 0,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Text(
                  item.badge > 99 ? '99+' : '${item.badge}',
                  textAlign: TextAlign.center,
                  style: FoE.dim(size: 8).copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
