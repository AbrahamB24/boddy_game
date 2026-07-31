import 'package:flutter/material.dart';
import '../../../core/theme/foe_theme.dart';

import '../../settlement/widgets/scroll_paper.dart' show kParchmentInk;

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

  const RecessBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 11,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    final r = height / 2;
    final wallInk = onDark ? Colors.black : kParchmentInk;
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, c) {
          // A bead narrower than the trough is round is a sliver, not a bar —
          // so a non-zero value always shows at least a full dot.
          final w = v <= 0
              ? 0.0
              : (c.maxWidth * v).clamp(height, c.maxWidth).toDouble();
          return ClipPath(
      clipper: ShapeBorderClipper(shape: FoE.facet(radius: r)),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: wallInk.withValues(alpha: onDark ? 0.32 : 0.11),
                    ),
                  ),
                ),
                // The groove's top lip, falling inward.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: height * 0.6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          wallInk.withValues(alpha: 0.28),
                          wallInk.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                // The far wall, in the light.
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: height * 0.4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.white.withValues(alpha: onDark ? 0.14 : 0.22),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                if (w > 0)
                  // Directional, not `left`: the breeding screen mirrors one of
                  // its two comparison bars with a [Directionality], and an
                  // absolute left would have pinned the bead to the wrong end.
                  PositionedDirectional(
                    start: 0,
                    top: 0,
                    bottom: 0,
                    width: w,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(r),
                        // Lit on top, darkening into its own colour at the
                        // foot — a bead lying in the groove, not a fill.
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color.lerp(color, Colors.white, 0.35)!,
                            color,
                            Color.lerp(color, Colors.black, 0.16)!,
                          ],
                          stops: const [0, 0.55, 1],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: wallInk.withValues(alpha: 0.35),
                            blurRadius: 0,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
