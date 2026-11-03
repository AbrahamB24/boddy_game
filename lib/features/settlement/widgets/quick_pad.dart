import 'package:flutter/material.dart';

import '../../../core/theme/cream_kit.dart';
import '../../../core/theme/foe_theme.dart';
import '../../../core/ui/pressable.dart';
import '../../../core/theme/voxel_kit.dart';
import '../../../core/theme/voxel_icons.dart';

/// One button on a [QuickRail].
class QuickPadItem {
  final IconData icon;

  /// Printed under the glyph and read out as the button's accessible name.
  final String label;

  final VoidCallback onTap;

  /// Drawn as a badge on the tile's corner when > 0 — unread events, claimable
  /// tasks, items in the bag.
  final int badge;

  /// Fills the tile amber. For the destination you are already looking at, or a
  /// state the player has to come back to.
  final bool active;

  /// When set, wraps this tile in a [KeyedSubtree] carrying the key — lets
  /// the guided tutorial's [IntroSpotlightOverlay] find and light up this
  /// exact tile (see [IntroSpotlightAnchors]).
  final Key? anchorKey;

  /// The button's own colour; null picks one by [label] (see [_accentFor]).
  final Color? accent;

  const QuickPadItem(
    this.icon,
    this.label,
    this.onTap, {
    this.badge = 0,
    this.active = false,
    this.anchorKey,
    this.accent,
  });
}

/// A ROW (or column) OF THE SETTLEMENT'S CONTROLS — round, colour-coded gem buttons:
/// each function has its own colour, amber when [QuickPadItem.active].
///
/// The main screen lays them out the way Forge of Empires does (user
/// 2026-09-19): the three places you go to constantly — Build, Monsters, Map —
/// as a HORIZONTAL row at the bottom right, and Social at the bottom left with
/// a [QuickDock] unfolding towards the right for everything else.
class QuickRail extends StatelessWidget {
  final List<QuickPadItem> items;
  final Axis axis;

  const QuickRail({
    super.key,
    required this.items,
    this.axis = Axis.horizontal,
  });

  static const double tile = 52;
  static const double gap = 10;

  @override
  Widget build(BuildContext context) => Flex(
    direction: axis,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0)
          SizedBox(
            width: axis == Axis.horizontal ? gap : 0,
            height: axis == Axis.vertical ? gap : 0,
          ),
        _anchored(items[i]),
      ],
    ],
  );

  static Widget _anchored(QuickPadItem item) {
    final t = _QuickTile(item: item);
    final key = item.anchorKey;
    return key == null ? t : KeyedSubtree(key: key, child: t);
  }
}

/// How far a button's hard shadow (3 + 6 px offset, 8 blur) and its corner badge
/// hang outside it — the room the drawer keeps free so neither is clipped.
const double _kHang = 14;

/// A clip that keeps the sides but lets a child paint [_kHang] above and below.
class _VerticalRoom extends CustomClipper<Rect> {
  const _VerticalRoom();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, -_kHang, size.width, size.height + _kHang);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}

/// SOCIAL, AND A DOOR TO THE REST (user 2026-09-19): the main tile stands at
/// the left edge; beside it a slim fold button opens a row to the RIGHT with
/// every other button ([more]) and closes it again. While it is closed, what
/// waits behind it — new bag items, claimable tasks — is counted on the fold
/// button, so nothing goes unseen just because it is folded away.
class QuickDock extends StatefulWidget {
  final QuickPadItem main;
  final List<QuickPadItem> more;

  const QuickDock({super.key, required this.main, required this.more});

  @override
  State<QuickDock> createState() => _QuickDockState();
}

class _QuickDockState extends State<QuickDock> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final hidden = widget.more.fold<int>(0, (n, i) => n + i.badge);
    // No door when there's nothing behind it (2026-10-01: the tutorial's own
    // solo hand-off hands this dock just its one lit tile, `more: []` — a
    // chevron that unfolds into empty space invites a tap for nothing).
    if (widget.more.isEmpty) return QuickRail._anchored(widget.main);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        QuickRail._anchored(widget.main),
        const SizedBox(width: QuickRail.gap),
        _foldButton(hidden),
        // The row grows out of the fold button; clipped so it never spills
        // while it animates.
        // Clipped to the row's own WIDTH while it animates, but free above and
        // below (user 2026-09-28: "die Notification ist abgeschnitten und unten
        // der Schatten von den Icons"): the badge on a button's corner and its
        // hard shadow hang outside the row. The room is a CLIP allowance, not
        // padding — padding made the open row taller, and the buttons on the left
        // are centred on it, so they climbed (user, same day: "die Buttons links
        // wandern nach oben"). Nothing here may change the row's height.
        ClipRect(
          clipper: const _VerticalRoom(),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.centerLeft,
            // The row stays MOUNTED either way now (user 2026-09-29: "beim
            // Zuklappen fehlt die Animation") — it used to be swapped for a
            // bare SizedBox.shrink() when closed, which unmounted the whole
            // QuickRail the instant `_open` flipped: the buttons vanished
            // before AnimatedSize had drawn a single frame, and only the
            // trailing empty space was left to visibly collapse. An `Align`
            // with a widthFactor keeps the row's own laid-out size honest
            // (0 when closed) without ever tearing it down, so AnimatedSize
            // now has something real to shrink — the same reveal-by-clipping
            // it already did on the way open, just running in reverse too.
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: _open ? 1 : 0,
              child: Padding(
                // Right: room for a badge that hangs past the last button.
                padding: const EdgeInsets.only(
                  left: QuickRail.gap,
                  right: _kHang,
                ),
                child: QuickRail(items: widget.more),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// A small round tab beside the Social button: ▸ closed, ◂ open (amber). Much
  /// smaller than the buttons it opens (user 2026-09-22: "kleiner sein, weniger
  /// hoch") — it is a door, not a destination — and centred on their row.
  Widget _foldButton(int hidden) => Semantics(
    label: _open ? 'Fold away' : 'More buttons',
    button: true,
    child: SizedBox(
      width: 24,
      height: 34,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Pressable(
              onTap: () => setState(() => _open = !_open),
              child: DecoratedBox(
                // The real gem chrome now, not `goldButton()`'s flat chunky
                // pill (user 2026-09-29: "es fehlt noch der weisse Rahmen
                // und der Farbverlauf, damit sie gleich sind wie die Buttons
                // Build und Management") — gradient, cream/white rim and
                // drop shadow, exactly [_QuickTile]'s own decoration.
                decoration: gemDecoration(
                  CreamPalette.gold,
                  lit: _open,
                  shape: BoxShape.rectangle,
                  borderRadius: vr(12),
                ),
                child: PixelIcon(
                  _open ? Icons.chevron_left : Icons.chevron_right,
                  size: 20,
                  color: CreamPalette.ink,
                ),
              ),
            ),
          ),
          if (!_open && hidden > 0)
            Positioned(top: -8, right: -8, child: _badge(hidden)),
        ],
      ),
    ),
  );
}

Widget _badge(int count) => Container(
  constraints: const BoxConstraints(minWidth: 19),
  height: 19,
  padding: const EdgeInsets.symmetric(horizontal: 5),
  alignment: Alignment.center,
  decoration: BoxDecoration(
    color: FoE.coral,
    borderRadius: vr(10),
    border: Border.all(color: CreamPalette.paperTop, width: 2),
  ),
  child: Text(
    count > 99 ? '99+' : '$count',
    style: const TextStyle(
      color: CreamPalette.ink,
      fontWeight: FontWeight.w800,
      fontSize: 10.5,
    ),
  ),
);

/// A button's colour. TWO tones only (user 2026-09-28: the main buttons all one
/// colour, the fold-out drawer's buttons one slightly different colour among
/// themselves), so the row reads as one family and the icons tell the buttons
/// apart. Deep amber keeps a white glyph readable.
Color _accentFor(QuickPadItem item) {
  if (item.accent != null) return item.accent!;
  // TWO colours, not one per button (user 2026-09-28: "Die Buttons … sollen alle
  // die gleiche Farbe haben. Die Unterbuttons … sind leicht anders, aber für sich
  // auch alle gleich"). The places you go to all the time wear the amber; what
  // sits in the fold-out drawer wears one quieter tone. The icon tells them apart.
  return switch (item.label) {
    'Build' ||
    'Monsters' ||
    'Map' ||
    'Manage' ||
    'Expedition' => CreamPalette.gold,
    'Social' || 'Profile' || 'Bag' || 'Daily tasks' => CreamPalette.goldDeep,
    _ => CreamPalette.tan,
  };
}

Color _lighten(Color c, double t) => Color.lerp(c, Colors.white, t)!;
Color _darken(Color c, double t) => Color.lerp(c, Colors.black, t)!;

/// The gold "gem" look every round quick-pad button is lit with — pulled out
/// so anything ELSE that wants to read as the same family of button (the
/// fold tab beside it, the news bell up in the header) can share the exact
/// gradient instead of drifting to its own colour (user 2026-09-29: "der
/// Aufklappbutton und der Notificationsbutton ... sollen die gleiche Farbe
/// haben wie Buttons Build, Management etc.").
RadialGradient gemGradient(Color accent) => RadialGradient(
  center: const Alignment(-0.35, -0.55),
  radius: 1.05,
  colors: [_lighten(accent, 0.38), accent, _darken(accent, 0.22)],
  stops: const [0, 0.55, 1],
);

/// The WHOLE gem chrome — gradient, rim and drop shadow — not just the
/// colour: the first pass only swapped in [gemGradient] and the fold tab and
/// the bell still read as a different button (user 2026-09-29: "es fehlt
/// noch der weisse Rahmen und der Farbverlauf, damit sie gleich sind wie die
/// Buttons Build und Management"). [shape] picks circle (the bell) or a
/// rounded rect (the fold tab, which is a narrow pill, not a disc); pass
/// [borderRadius] only for the rect case.
BoxDecoration gemDecoration(
  Color accent, {
  bool lit = false,
  BoxShape shape = BoxShape.rectangle,
  BorderRadius? borderRadius,
}) => BoxDecoration(
  shape: shape,
  borderRadius: shape == BoxShape.rectangle
      ? (borderRadius ?? vr(12))
      : null,
  // VOXEL (2026-11-03): one flat block of the accent colour, a dark outline
  // (white while lit) and a hard slab of shadow. No gradient, no blur.
  color: accent,
  border: Border.all(
    color: lit ? Colors.white : Voxel.outline,
    width: lit ? 3 : 2.5,
  ),
  boxShadow: [
    BoxShadow(color: _darken(accent, 0.55), offset: const Offset(0, 4)),
  ],
);

/// A ROUND GEM BUTTON: the accent colour lit from the top left, a cream rim, a
/// glossy highlight across the top and a hard shadow underneath, the glyph big and
/// white (ink on the light amber ones). Icon only; the label is the accessible
/// name and the tooltip.
class _QuickTile extends StatelessWidget {
  final QuickPadItem item;

  const _QuickTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final lit = item.active;
    final accent = lit ? CreamPalette.gold : _accentFor(item);
    final light = accent.computeLuminance() > 0.45;
    final ink = light ? CreamPalette.ink : Colors.white;
    const d = QuickRail.tile;
    return Semantics(
      label: item.label,
      button: true,
      child: Tooltip(
        message: item.label,
        child: SizedBox(
          width: d,
          height: d,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Pressable(
                  onTap: item.onTap,
                  child: DecoratedBox(
                    decoration: gemDecoration(accent, lit: lit),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // The gloss: a pale, curved highlight across the top.
                        Positioned(
                          top: 3,
                          left: 9,
                          right: 9,
                          height: 15,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: vr(10),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.white.withValues(
                                    alpha: light ? 0.55 : 0.42,
                                  ),
                                  Colors.white.withValues(alpha: 0),
                                ],
                              ),
                            ),
                          ),
                        ),
                        PixelIcon(
                          item.icon,
                          size: 27,
                          color: ink,
                          shadows: light
                              ? null
                              : const [
                                  Shadow(
                                    color: Color(0x66000000),
                                    offset: Offset(0, 1.5),
                                    blurRadius: 2,
                                  ),
                                ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (item.badge > 0)
                Positioned(top: -5, right: -5, child: _badge(item.badge)),
            ],
          ),
        ),
      ),
    );
  }
}
