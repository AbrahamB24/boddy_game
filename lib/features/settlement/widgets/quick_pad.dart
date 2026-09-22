import 'package:flutter/material.dart';

import '../../../core/theme/cream_kit.dart';
import '../../../core/theme/foe_theme.dart';
import '../../../core/ui/pressable.dart';

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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        QuickRail._anchored(widget.main),
        const SizedBox(width: QuickRail.gap),
        _foldButton(hidden),
        // The row grows out of the fold button; clipped so it never spills
        // while it animates.
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.centerLeft,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.only(left: QuickRail.gap),
                    child: QuickRail(items: widget.more),
                  )
                : const SizedBox.shrink(),
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
                decoration: _open
                    ? goldButton().copyWith(
                        borderRadius: BorderRadius.circular(12),
                      )
                    : raisedTile(radius: 12),
                child: Icon(
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
    borderRadius: BorderRadius.circular(10),
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

/// Each button's own colour (user 2026-09-22: "die Buttons wirken noch ziemlich
/// langweilig"): a function has a colour, so the row reads as a row of different
/// things instead of five identical cream tiles. Earthy and saturated enough to
/// hold on the green map and on the brown build strip alike.
Color _accentFor(QuickPadItem item) {
  if (item.accent != null) return item.accent!;
  return switch (item.label) {
    'Build' => CreamPalette.gold,
    'Monsters' => const Color(0xFF4FA36B),
    'Map' => const Color(0xFF3F8FB5),
    'Social' => const Color(0xFFE0674F),
    'Manage' => const Color(0xFF9C6B3E),
    'Profile' => const Color(0xFF7B62B3),
    'Bag' => const Color(0xFFD9822B),
    'Daily tasks' => const Color(0xFF2FA394),
    _ => CreamPalette.tan,
  };
}

Color _lighten(Color c, double t) => Color.lerp(c, Colors.white, t)!;
Color _darken(Color c, double t) => Color.lerp(c, Colors.black, t)!;

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
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-0.35, -0.55),
                        radius: 1.05,
                        colors: [
                          _lighten(accent, 0.38),
                          accent,
                          _darken(accent, 0.22),
                        ],
                        stops: const [0, 0.55, 1],
                      ),
                      border: Border.all(
                        color: lit
                            ? Colors.white
                            : CreamPalette.paperTop.withValues(alpha: 0.95),
                        width: lit ? 3 : 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _darken(accent, 0.55),
                          offset: const Offset(0, 3),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28),
                          blurRadius: 8,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
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
                              borderRadius: BorderRadius.circular(10),
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
                        Icon(
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
