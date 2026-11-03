import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'voxel_kit.dart' show vr;

// ── Fachwerk: the UI's materials, taken from the buildings ──────────────────
//
// User 2026-11-02, showing the new Blender-rendered Breeding Hut (terracotta
// roof tiles, dark timber framing over pale plaster, rubble stone, grass,
// teal/yellow shutters, warm lit windows): "ich mache die Gebäude nun in
// diesem Stil. Kannst du das UI komplett daran anpassen?"
//
// The kit stays the kit — same cards, buttons and layouts — but it is now
// BUILT from those materials instead of flat sand and amber:
//
//  * [Fachwerk] — the colours, sampled from the render.
//  * [paintTimberFrame] — a dark beam around a main surface, with grain and a
//    peg in each corner, the way the house's posts frame its plaster.
//  * [paintRoofTiles] / [RoofTileStrip] — a staggered row of terracotta tiles
//    with the render's tile-to-tile colour variation; the "roof" over a title.
//  * [paintPlaster] — a faint, fixed speckle so a surface reads as rendered
//    plaster rather than a flat fill.
//
// All painters are deterministic (a seeded hash, never Random()) so a card
// looks the same on every frame and every repaint.

abstract final class Fachwerk {
  // Roof tiles — base, lit, shaded, and the dark gap between tiles.
  static const Color tile = Color(0xFFC9622E);
  static const Color tileLight = Color(0xFFE58B4C);
  static const Color tileDark = Color(0xFF8E3B1C);
  static const Color tileGap = Color(0xFF5C2412);

  // Timber beams.
  static const Color timber = Color(0xFF25596B);
  static const Color timberLight = Color(0xFF3A7F96);
  static const Color timberDark = Color(0xFF143E4C);

  // Plaster.
  static const Color plaster = Color(0xFFF6EFE0);
  static const Color plasterShade = Color(0xFFE6D6B8);

  // Accents from the render.
  static const Color shutterTeal = Color(0xFF3F8E8C);
  static const Color shutterYellow = Color(0xFFE2B53E);
  static const Color grass = Color(0xFF7FA83A);
  static const Color grassDark = Color(0xFF4F7A26);
  static const Color stone = Color(0xFFB4A48A);
  static const Color windowGlow = Color(0xFFFFD27A);
}

/// A cheap, stable 0..1 hash — the painters' only source of variation.
double _hash(int a, int b) {
  var h = a * 374761393 + b * 668265263;
  h = (h ^ (h >> 13)) * 1274126177;
  h = h ^ (h >> 16);
  return (h & 0xFFFF) / 0xFFFF;
}

/// Speckles [rect] with plaster grain: a few hundred tiny light and dark
/// dots at most, laid on a fixed grid with hashed jitter. Call with the
/// canvas already clipped to the surface.
void paintPlaster(Canvas canvas, Rect rect, {double opacity = 1}) {
  if (!rect.isFinite || rect.isEmpty) return;
  const step = 9.0;
  final light = <Offset>[];
  final dark = <Offset>[];
  var i = 0;
  for (var y = rect.top; y < rect.bottom; y += step) {
    var j = 0;
    for (var x = rect.left; x < rect.right; x += step) {
      final h = _hash(i, j);
      final p = Offset(
        x + _hash(j, i + 7) * step,
        y + _hash(i + 3, j + 11) * step,
      );
      if (h < 0.22) {
        dark.add(p);
      } else if (h > 0.80) {
        light.add(p);
      }
      j++;
    }
    i++;
  }
  canvas.drawPoints(
    PointMode.points,
    dark,
    Paint()
      ..color = Fachwerk.timber.withValues(alpha: 0.10 * opacity)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round,
  );
  canvas.drawPoints(
    PointMode.points,
    light,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.35 * opacity)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round,
  );
}

/// Paints a timber beam [width] wide around the inside edge of [outer]: a
/// lit-to-shaded wood gradient, a few grain lines along each side, a thin
/// light chamfer on the inner edge and a peg in every corner.
void paintTimberFrame(Canvas canvas, RRect outer, {double width = 6}) {
  if (!outer.outerRect.isFinite || outer.outerRect.isEmpty) return;
  final inner = outer.deflate(width);
  final ring = Path()
    ..fillType = PathFillType.evenOdd
    ..addRRect(outer)
    ..addRRect(inner);
  final r = outer.outerRect;
  canvas.drawPath(
    ring,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Fachwerk.timberLight, Fachwerk.timber, Fachwerk.timberDark],
        stops: [0, 0.55, 1],
      ).createShader(r),
  );

  // Grain: short darker strokes running along each beam.
  canvas.save();
  canvas.clipPath(ring);
  final grain = Paint()
    ..color = Fachwerk.timberDark.withValues(alpha: 0.45)
    ..strokeWidth = 0.8;
  var k = 0;
  for (var x = r.left + 6; x < r.right - 6; x += 23) {
    final len = 10 + _hash(k, 1) * 18;
    final dy = 1.5 + _hash(k, 2) * (width - 3);
    canvas.drawLine(Offset(x, r.top + dy), Offset(x + len, r.top + dy), grain);
    canvas.drawLine(
      Offset(x + 7, r.bottom - dy),
      Offset(x + 7 + len, r.bottom - dy),
      grain,
    );
    k++;
  }
  for (var y = r.top + 6; y < r.bottom - 6; y += 23) {
    final len = 10 + _hash(k, 3) * 18;
    final dx = 1.5 + _hash(k, 4) * (width - 3);
    canvas.drawLine(
      Offset(r.left + dx, y),
      Offset(r.left + dx, y + len),
      grain,
    );
    canvas.drawLine(
      Offset(r.right - dx, y + 5),
      Offset(r.right - dx, y + 5 + len),
      grain,
    );
    k++;
  }
  canvas.restore();

  // The chamfer where beam meets plaster, then a soft shade cast inward.
  canvas.drawRRect(
    inner,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1,
  );
  canvas.drawRRect(
    inner.deflate(1.5),
    Paint()
      ..color = Fachwerk.timberDark.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );

  // Pegs.
  final pr = math.max(1.6, width * 0.28);
  for (final c in [
    Offset(r.left + width / 2, r.top + width / 2),
    Offset(r.right - width / 2, r.top + width / 2),
    Offset(r.left + width / 2, r.bottom - width / 2),
    Offset(r.right - width / 2, r.bottom - width / 2),
  ]) {
    canvas.drawCircle(c, pr, Paint()..color = Fachwerk.timberDark);
    canvas.drawCircle(
      c.translate(-pr * 0.3, -pr * 0.3),
      pr * 0.45,
      Paint()..color = Fachwerk.timberLight.withValues(alpha: 0.8),
    );
  }
}

/// Paints a band of roof tiles across [rect]: two staggered courses of
/// round-bottomed tiles, each one shaded from lit top to dark foot, with the
/// render's gentle tile-to-tile colour variation, over a dark gap colour.
void paintRoofTiles(Canvas canvas, Rect rect, {double tileWidth = 15}) {
  // VOXEL (2026-11-03): no tiles any more (user: the Fachwerk/brick header is
  // gone). The "roof" is now a plain flat band of the chrome colour with a lit
  // top edge and a dark block foot, the same bevel every other piece has.
  if (!rect.isFinite || rect.isEmpty) return;
  canvas.drawRect(rect, Paint()..color = Fachwerk.timber);
  canvas.drawRect(
    Rect.fromLTWH(rect.left, rect.top, rect.width, 2),
    Paint()..color = Fachwerk.timberLight,
  );
  canvas.drawRect(
    Rect.fromLTWH(rect.left, rect.bottom - 3, rect.width, 3),
    Paint()..color = Fachwerk.timberDark,
  );
}

/// A row of roof tiles as a widget — for a header's foot or a title's crown.
class RoofTileStrip extends StatelessWidget {
  final double height;
  final double tileWidth;
  const RoofTileStrip({super.key, this.height = 12, this.tileWidth = 15});

  @override
  // No width of its own: it takes whatever its parent allows (a stretched
  // Column, a fixed box). An explicit double.infinity once handed the
  // painter an infinite rect inside an IntrinsicWidth — and its tile loop
  // never ended.
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: CustomPaint(painter: _RoofPainter(tileWidth), size: Size.infinite),
  );
}

class _RoofPainter extends CustomPainter {
  final double tileWidth;
  const _RoofPainter(this.tileWidth);

  @override
  void paint(Canvas canvas, Size size) =>
      paintRoofTiles(canvas, Offset.zero & size, tileWidth: tileWidth);

  @override
  bool shouldRepaint(covariant _RoofPainter old) => old.tileWidth != tileWidth;
}

/// A timber beam as a horizontal band (the main screen's header plate):
/// wood gradient with grain, a lit top edge and a shaded foot.
void paintTimberBand(Canvas canvas, Rect rect) {
  if (!rect.isFinite || rect.isEmpty) return;
  // VOXEL (2026-11-03): flat, no wood grain or gradient.
  canvas.drawRect(rect, Paint()..color = Fachwerk.timber);
  canvas.drawRect(
    Rect.fromLTWH(rect.left, rect.top, rect.width, 2),
    Paint()..color = Fachwerk.timberLight,
  );
  canvas.drawRect(
    Rect.fromLTWH(rect.left, rect.bottom - 3, rect.width, 3),
    Paint()..color = Fachwerk.timberDark,
  );
}

/// A timber plank as a widget — a sign, a name plate: [paintTimberBand]
/// clipped to rounded corners, with a peg at each end.
class TimberPlate extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  const TimberPlate({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: vr(radius),
      boxShadow: const [
        BoxShadow(color: Color(0x6B000000), offset: Offset(0, 3)),
      ],
    ),
    child: CustomPaint(
      painter: _PlatePainter(radius),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class _PlatePainter extends CustomPainter {
  final double radius;
  const _PlatePainter(this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.save();
    canvas.clipRRect(rr);
    paintTimberBand(canvas, Offset.zero & size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PlatePainter old) => old.radius != radius;
}
