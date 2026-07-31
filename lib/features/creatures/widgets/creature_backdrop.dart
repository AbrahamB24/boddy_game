import 'package:flutter/material.dart';
import '../../../core/theme/foe_theme.dart';

import '../models/creature_enums.dart';

/// Card backdrop for a creature's art (user 2026-07-17): a smooth diagonal
/// gradient in the creature's ELEMENT colour (lighter top-left → deeper
/// bottom-right) with the ELEMENT SYMBOL itself built into the background as a
/// large, faint, tone-on-tone watermark bleeding off the bottom-right corner.
///
/// A monster tile is ONE colour — its type's — since 2026-07-27. It used to be
/// element behind the art and RARITY behind the name; the rarity half is gone,
/// and with it the `rarity` parameter this widget accepted and never painted.
class CreatureBackdrop extends StatelessWidget {
  final CreatureElement element;
  final Widget child;
  final double radius;
  final EdgeInsets padding;

  /// Puts the element-symbol watermark in the bottom-LEFT instead of the
  /// bottom-right — used on the battle screen for the enemy, whose sprite sits
  /// on the right (user 2026-07-18).
  final bool watermarkLeft;

  /// Multiplier on the watermark symbol's size — the battle screen passes a
  /// larger value for bigger type icons (user 2026-07-18); 1.0 elsewhere.
  final double symbolScale;

  /// Anchors the watermark to the TOP edge (bleeding off the top + side) instead
  /// of the bottom — the battle screen wants the big type icon to peek out the
  /// top corner (user 2026-07-18).
  final bool watermarkTop;

  /// Overrides for reusing this exact tile look on NON-type buttons (the battle
  /// deck's Auto/Items/Change/Catch/End Turn): [symbol] replaces the element's
  /// emoji watermark, [baseColor] replaces the element colour that drives the
  /// gradient + emboss. Both default to the element's own values.
  final String? symbol;
  final Color? baseColor;

  /// A VECTOR icon watermark instead of an emoji [symbol] — used by the battle
  /// deck buttons so their glyphs render identically on every platform (no
  /// emoji-font dependency, user request 2026-07-20). Takes precedence over
  /// [symbol] when set.
  final IconData? iconSymbol;

  const CreatureBackdrop({
    super.key,
    required this.element,
    required this.child,
    this.radius = 8,
    this.padding = EdgeInsets.zero,
    this.watermarkLeft = false,
    this.symbolScale = 1.0,
    this.watermarkTop = false,
    this.symbol,
    this.baseColor,
    this.iconSymbol,
  });

  @override
  Widget build(BuildContext context) => ClipPath(
      clipper: ShapeBorderClipper(shape: FoE.facet(radius: radius)),
    child: CustomPaint(
      painter: _GradientBackdrop(baseColor ?? element.color),
      child: LayoutBuilder(
        builder: (context, c) {
          final s = c.biggest.shortestSide;
          return Stack(
            fit: StackFit.expand,
            children: [
              // The element symbol as a background watermark, embossed to read
              // as 3D (user 2026-07-18): a dark bottom-right face and a light
              // top-left highlight peek out from behind the mid-tone body, a
              // low-relief extrude in the element's own colour.
              Positioned(
                right: watermarkLeft ? null : (watermarkTop ? -s * 0.13 : -s * 0.04),
                left: watermarkLeft ? (watermarkTop ? -s * 0.13 : -s * 0.04) : null,
                top: watermarkTop ? -s * 0.15 : null,
                bottom: watermarkTop ? null : -s * 0.06,
                child: Opacity(
                  opacity: 0.36,
                  child: _embossedSymbol(s),
                ),
              ),
              Padding(padding: padding, child: child),
            ],
          );
        },
      ),
    ),
  );

  /// The symbol used for the type WATERMARK only (not the element's emoji
  /// everywhere else): water reads better as a wave than a droplet at this
  /// scale (user 2026-07-18).
  static String _backdropSymbol(CreatureElement element) =>
      element == CreatureElement.water ? '🌊' : element.emoji;

  /// The watermark symbol as a low-relief 3D emboss (user 2026-07-18): the same
  /// silhouette drawn in three tones — a dark face nudged down-right, a light
  /// highlight nudged up-left, and the mid-tone body on top — so the edges
  /// catch light like an extruded shape.
  Widget _embossedSymbol(double s) {
    final base = baseColor ?? element.color;
    final fontSize = s * 0.55 * symbolScale;
    final d = fontSize * 0.02; // extrude depth — subtle, scales with the glyph
    final glyph = symbol ?? _backdropSymbol(element);
    // A vector icon (deck buttons) renders identically everywhere; an emoji
    // glyph (type watermark) keeps the colourful type look.
    Widget face(Color c) => ColorFiltered(
      colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
      child: iconSymbol != null
          ? Icon(iconSymbol, size: fontSize, color: Colors.white)
          : Text(glyph, style: TextStyle(fontSize: fontSize)),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Dark bottom-right face — the extruded side in shadow. Same tone as a
        // monster's drop shadow: lerp(base, black, 0.32) (= element.shadowColor
        // when no baseColor override is given).
        Transform.translate(
          offset: Offset(d, d),
          child: face(Color.lerp(base, Colors.black, 0.32)!),
        ),
        // Light top-left highlight — the lit edge.
        Transform.translate(
          offset: Offset(-d * 0.7, -d * 0.7),
          child: face(Color.lerp(base, Colors.white, 0.8)!),
        ),
        // Mid-tone body on top.
        face(Color.lerp(base, Colors.white, 0.6)!),
      ],
    );
  }
}

class _GradientBackdrop extends CustomPainter {
  final Color color;
  const _GradientBackdrop(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Smooth diagonal gradient: an airy tint of the element top-left fading to a
    // deeper element tone bottom-right.
    final a = Color.lerp(color, Colors.white, 0.30)!;
    final b = Color.lerp(color, Colors.black, 0.20)!;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [a, b],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GradientBackdrop old) => old.color != color;
}
