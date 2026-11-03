import 'package:flutter/material.dart';

import '../../../core/theme/voxel_kit.dart';

/// EVERY BAR IN THE GAME (user 2026-07-29: "jetzt alle Balken im gleichen
/// Effekt gestalten" + "ev. etwas dicker machen, damit es sichtbar ist").
///
/// They were all [LinearProgressIndicator]s: a flat tinted strip in a flat
/// grey one. On a page whose cards are cut into the paper and whose buttons are
/// keys with a travel, a flat bar was the last thing still drawn as a diagram.
///
/// This is the same two-part construction as everything else:
///
///  • THE TROUGH is a groove — a faint fill, an inner shadow falling in from
///    the top lip, and the far wall catching the light along the bottom;
///  • THE FILL is a raised bead lying in it, lit along its own top edge and
///    casting a short shadow down into the groove.
///
/// [height] defaults to 11 rather than the 5–8 the old bars used: the walls and
/// the bead need room to be seen at all, and a bar you have to look for is not
/// doing its job either way.
///
/// The bead's WIDTH animates (user 2026-09-15: "der Balken wird sichtbar
/// 'grösser' während dem heilen") via [AnimatedPositionedDirectional] — a
/// value change between two builds (a heal landing, damage taken, a build
/// finishing a tick) now visibly grows/shrinks over [animationDuration]
/// instead of snapping straight to the new fraction. [animationDuration]
/// defaults to a quick, snappy tick suited to combat; a screen that reads
/// its own value from a slow ongoing process (a countdown timer already
/// interpolating on its own) can pass [Duration.zero] to keep the old
/// instant behaviour.
class RecessBar extends StatelessWidget {
  /// 0–1. Values outside are clamped.
  final double value;

  /// The bead's colour — HP green, an element tint, the gold of a countdown.
  final Color color;

  final double height;

  /// Set on a DARK surface (the battle screen's plates): the groove's shadow
  /// and its lit lip swap roles, because the light still comes from above but
  /// the material underneath is no longer pale paper.
  final bool onDark;

  /// How long the bead takes to glide to a new [value]. Zero = the old
  /// instant snap.
  final Duration animationDuration;

  const RecessBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 11,
    this.onDark = false,
    this.animationDuration = const Duration(milliseconds: 350),
  });

  /// VOXEL (2026-11-03): every bar in the game is a row of blocks now â€” see
  /// [VoxelBar]. The value still glides to its new level ([animationDuration]),
  /// block by block.
  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: v),
      duration: animationDuration,
      curve: Curves.easeOut,
      builder: (context, shown, _) => VoxelBar(
        value: shown,
        color: color,
        height: height,
        block: height < 10 ? 6 : 8,
        onDark: onDark,
      ),
    );
  }
}