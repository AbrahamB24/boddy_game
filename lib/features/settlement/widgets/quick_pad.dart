import 'package:flutter/material.dart' hide Text;

import '../../../core/theme/fachwerk.dart';
import '../../../core/theme/cream_kit.dart';
import '../../../core/theme/ui_art.dart';
import '../../../core/theme/foe_theme.dart';
import '../../../core/ui/pressable.dart';
import '../../../core/theme/voxel_kit.dart';
import '../../../core/theme/voxel_icons.dart';
import '../../../core/ui/game_text.dart';

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

  /// Drawn as the compass-and-globe button instead of a round iron one (the
  /// main tile of the bottom-left corner).
  final bool compass;

  const QuickPadItem(
    this.icon,
    this.label,
    this.onTap, {
    this.badge = 0,
    this.active = false,
    this.anchorKey,
    this.accent,
    this.compass = false,
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

  static const double tile = 64;
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
    // BOTTOM-aligned (user 2026-11-04: the small icons must stand on the same
    // line as the ones on the right, not float at the big compass's middle);
    // the fold plate is centred on that one line of tiles.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        QuickRail._anchored(widget.main),
        // Right up against the compass (user 2026-11-04: "näher an Expedition").
        const SizedBox(width: 1),
        // At the compass's BOTTOM RIGHT (user 2026-11-04: "unten rechts von
        // Expeditions"), tucked 12 px over its edge; it keeps its own tap area.
        Transform.translate(
          offset: const Offset(-12, 0),
          child: _foldButton(hidden),
        ),
        // Clipped to the row's own WIDTH while it animates, but free above and
        // below (user 2026-09-28: "die Notification ist abgeschnitten und unten
        // der Schatten von den Icons"): the badge on a button's corner and its
        // hard shadow hang outside the row. The room is a CLIP allowance, not
        // padding — padding made the open row taller, and the buttons on the
        // left are centred on it, so they climbed (user, same day: "die Buttons
        // links wandern nach oben"). Nothing here may change the row's height.
        ClipRect(
          clipper: const _VerticalRoom(),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.centerLeft,
            // The row stays MOUNTED either way (user 2026-09-29: "beim
            // Zuklappen fehlt die Animation"): an `Align` with a widthFactor
            // keeps the row's own laid-out size honest (0 when closed) without
            // tearing it down, so AnimatedSize has something real to shrink.
            child: Align(
              alignment: Alignment.bottomLeft,
              widthFactor: _open ? 1 : 0,
              heightFactor: 1,
              child: Padding(
                // Right: room for a badge that hangs past the last button.
                padding: const EdgeInsets.only(right: _kHang),
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
      width: 40,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Pressable(
              onTap: () => setState(() => _open = !_open),
              child: IronButton(
                size: 40,
                lit: _open,
                child: PixelIcon(
                  _open ? Icons.chevron_left : Icons.chevron_right,
                  size: 19,
                  color: _open
                      ? const Color(0xFFFFE9B0)
                      : const Color(0xFF8FD98F),
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
      fontWeight: FontWeight.w400,
      fontSize: 11,
    ),
  ),
);

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
  BoxShape shape = BoxShape.circle,
  BorderRadius? borderRadius,
}) => BoxDecoration(
  shape: shape,
  borderRadius: shape == BoxShape.rectangle ? (borderRadius ?? vr(12)) : null,
  // PERGAMENT UND STEIN (2026-11-04): a round IRON button — the accent lit from
  // the top left, a dark rim (a brass-lit one while pressed) and a hard slab of
  // shadow underneath.
  gradient: RadialGradient(
    center: const Alignment(-0.35, -0.5),
    radius: 1.0,
    colors: [_lighten(accent, 0.35), accent, _darken(accent, 0.4)],
    stops: const [0, 0.5, 1],
  ),
  border: Border.all(
    color: lit ? HudBlocks.litRim : HudBlocks.mossDark,
    width: lit ? 3 : 2.5,
  ),
  boxShadow: const [
    BoxShadow(color: Color(0x8C000000), offset: Offset(0, 4), blurRadius: 3),
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
    final d = item.compass ? 108.0 : QuickRail.tile;
    final art = UiArt.iconFor(item.label);
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
                  // Rendered iron button / compass (user 2026-11-04, painted
                  // concept); the glyph sits on its dark dish.
                  // The compass picture leaves 6 px of air under its ring at this
                  // size, the iron buttons only 2.4: pushed down by the difference
                  // so the visible bottoms of ALL icons stand on one line (user
                  // 2026-11-04).
                  child: item.compass
                      // No lift any more: the timber board has no air under it.
                      ? CompassButton(size: d)
                      // The medal: timber ring round a beige (plaster) dish, the
                      // glyph on it (user 2026-11-05: "bei allen Icons den beigen
                      // Hintergrund und den Holzrahmen").
                      : IronButton(
                          size: d,
                          lit: lit,
                          // The rendered 3D glyph where there is one, else the
                          // flat icon.
                          child: art != null
                              ? Image.asset(
                                  art,
                                  width: d * 0.64,
                                  height: d * 0.64,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.medium,
                                  gaplessPlayback: true,
                                )
                              : PixelIcon(
                                  item.icon,
                                  size: 26,
                                  color: lit
                                      ? const Color(0xFFFFE9B0)
                                      : const Color(0xFFEFE2BC),
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
