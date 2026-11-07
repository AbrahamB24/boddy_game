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

// ─────────────────────────────────────────────────────────────────────────────
// MAIN-SCREEN HUD: "OZEANRIFF" (user 2026-11-04, palette no. 18 of the
// colour concepts: deep-sea panels, light blue for action, icy ink; it was no. 13,
// aubergine, for a few hours)
//
// The header is a DEEP-SEA slab with a light-blue rim, every figure sits on its
// own lighter plaque in cream ink, and the round buttons are sea-blue with a
// light-blue ring when lit. Only the settlement screen's HUD wears these. (The
// constant NAMES come from the earlier stone-and-moss HUD, then the parchment
// one, and are kept so no call site had to change: "stone" is the header
// surface, "moss" the round buttons.)
// ─────────────────────────────────────────────────────────────────────────────
abstract final class HudBlocks {
  // The header surface, lit → shaded.
  static const Color stoneLight = Color(0xFF1585D0);
  static const Color stone = Color(0xFF0A66B0);
  static const Color stoneDark = Color(0xFF064F8F);
  // The darkest edge: rim shadow and the trim's foot.
  static const Color stoneMortar = Color(0xFF00A6B8);

  // Round buttons: the main row, its shade, the drawer's quieter tone.
  static const Color moss = Color(0xFF1A86D6);
  static const Color mossDark = Color(0xFF04305C);
  static const Color mossDeep = Color(0xFF0E68B0);
  // Lit / pressed: the light blue of the loading bar (user 2026-11-04: "aus dem
  // Rot das hellere Blau, das den Ladebalken ausfüllt"), once coral.
  static const Color accent = Color(0xFF1FE6E0);

  // Cream ink on the dark surface, its quieter weight, and the plaque's tones.
  static const Color ink = Color(0xFFE6FBFF);
  static const Color inkSoft = Color(0xFF9CC8DB);
  static const Color plaqueTop = Color(0xFF1F8FD8);
  static const Color plaqueBottom = Color(0xFF0F6CB4);
  static const Color plaqueEdge = Color(0xFF04305C);

  // States read ON the dark surface.
  static const Color warn = Color(0xFFFF4560);
  static const Color good = Color(0xFF4DFF98);

  /// Light ink for a glyph on a round button.
  static const Color glyph = Color(0xFFE6FBFF);

  /// The ring of a lit (pressed / open) button.
  static const Color litRim = Color(0xFFE6FBFF);
}

// ── GOLD FILIGREE (user 2026-11-04, ornament proposal no. 1 of the fantasy
// round): gilded scrollwork under the header and along the screen's foot, jewels
// set in it, a gold flourish in each corner of the map.
// ───────────────────────────────────────────────────────────────────────────

const Color _kGoldLight = Color(0xFFFFF2B8);
const Color _kGold = Color(0xFFE8BF4A);
const Color _kGoldDeep = Color(0xFF9A6A1C);
const Color _kGoldDark = Color(0xFF5A3D10);

Shader _goldShader(Rect r, {bool vertical = false}) => LinearGradient(
  begin: vertical ? Alignment.topCenter : Alignment.topLeft,
  end: vertical ? Alignment.bottomCenter : Alignment.bottomRight,
  colors: const [_kGoldLight, _kGold, _kGoldDeep, _kGold, Color(0xFF7A5214)],
  stops: const [0, 0.25, 0.55, 0.8, 1],
).createShader(r);

/// A string of S-shaped scrolls along [y] from 0 to [width], with a small curl
/// above and below each bend, stroked in gold.
void _paintScrollBand(Canvas canvas, double width, double y, {double period = 24}) {
  if (!width.isFinite || width <= 0) return;
  final line = Path()..moveTo(0, y);
  final curls = Path();
  for (var x = 0.0; x < width; x += period) {
    line
      ..quadraticBezierTo(x + period / 4, y - 3.2, x + period / 2, y)
      ..quadraticBezierTo(x + period * 0.75, y + 3.2, x + period, y);
    curls
      ..addArc(
        Rect.fromCircle(center: Offset(x + period / 4, y - 5), radius: 2.1),
        0.6,
        4.6,
      )
      ..addArc(
        Rect.fromCircle(center: Offset(x + period * 0.75, y + 5), radius: 2.1),
        3.74,
        4.6,
      );
  }
  final shader = _goldShader(Rect.fromLTWH(0, y - 6, width, 12), vertical: true);
  canvas.drawPath(
    line,
    Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round,
  );
  canvas.drawPath(
    curls,
    Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round,
  );
}

/// A jewel in a gold bezel: [light] to [dark] radial, with a white glint.
void _paintJewel(Canvas canvas, Offset c, double r, Color light, Color mid, Color dark) {
  canvas.drawCircle(
    c.translate(0.3, 0.7),
    r + 0.9,
    Paint()..color = Colors.black.withValues(alpha: 0.45),
  );
  canvas.drawCircle(
    c,
    r + 0.9,
    Paint()..shader = _goldShader(Rect.fromCircle(center: c, radius: r + 1)),
  );
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.45),
        radius: 0.95,
        colors: [light, mid, dark],
        stops: const [0, 0.45, 1],
      ).createShader(Rect.fromCircle(center: c, radius: r)),
  );
  canvas.drawOval(
    Rect.fromCenter(center: c.translate(-r * 0.3, -r * 0.35), width: r * 0.8, height: r * 0.45),
    Paint()..color = Colors.white.withValues(alpha: 0.7),
  );
}

void _paintRuby(Canvas canvas, Offset c, double r) =>
    _paintJewel(canvas, c, r, const Color(0xFFFFB3B9), const Color(0xFFD4243A), const Color(0xFF5A0A18));
void _paintSapphire(Canvas canvas, Offset c, double r) =>
    _paintJewel(canvas, c, r, const Color(0xFFC9F3FF), const Color(0xFF2A8FD6), const Color(0xFF0A2F6A));

/// The header's foot: a gold bar with a lit and a shaded edge, scrollwork under
/// it and four jewels set in it. (Class name kept from the stone course and the
/// rivet rim it replaced.)
class StoneCourseStrip extends StatelessWidget {
  final double height;
  final double blockWidth;
  const StoneCourseStrip({super.key, this.height = 13, this.blockWidth = 22});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: CustomPaint(
      painter: const _GoldTrimPainter(),
      size: Size.infinite,
    ),
  );
}

class _GoldTrimPainter extends CustomPainter {
  const _GoldTrimPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (!size.isFinite || size.isEmpty) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = HudBlocks.stoneDark);
    final bar = Rect.fromLTWH(0, 0, size.width, 3);
    canvas.drawRect(bar, Paint()..shader = _goldShader(bar, vertical: true));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 0.8),
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 3, size.width, 1),
      Paint()..color = const Color(0x992A1C08),
    );
    _paintScrollBand(canvas, size.width, 8.6);
    final y = 7.4;
    _paintSapphire(canvas, Offset(size.width * 0.15, y), 3);
    _paintRuby(canvas, Offset(size.width * 0.3, y), 3.4);
    _paintRuby(canvas, Offset(size.width * 0.7, y), 3.4);
    _paintSapphire(canvas, Offset(size.width * 0.85, y), 3);
  }

  @override
  bool shouldRepaint(covariant _GoldTrimPainter old) => false;
}

/// The frame over the map: a scrollwork band along the screen's foot and a gold
/// flourish in each of the map's four corners. Paints only; it never takes a
/// touch, so wrap it in an [IgnorePointer].
class FiligreeFrame extends StatelessWidget {
  /// Where the map's top edge is (under the header).
  final double top;

  /// The band along the foot hangs this high.
  final double bottomHeight;

  const FiligreeFrame({super.key, required this.top, this.bottomHeight = 13});

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _FiligreeFramePainter(top, bottomHeight),
    size: Size.infinite,
  );
}

class _FiligreeFramePainter extends CustomPainter {
  final double top;
  final double bottomHeight;
  const _FiligreeFramePainter(this.top, this.bottomHeight);

  static Path _flourish() => Path()
    ..moveTo(0, 0)
    ..lineTo(14, 0)
    ..cubicTo(14, 3, 11, 4, 9, 3)
    ..cubicTo(8, 2, 9, 0.8, 10.4, 1.2)
    ..lineTo(3, 1.2)
    ..lineTo(3, 8)
    ..cubicTo(4, 8, 4.8, 9, 4, 10)
    ..cubicTo(3, 11, 0.6, 10, 0.6, 7.5)
    ..lineTo(0.6, 0)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    if (!size.isFinite || size.isEmpty) return;
    final w = size.width, h = size.height;
    // The foot: a dim backing so the scrollwork reads on any ground, a gold
    // rule, the scrolls.
    // bottomHeight 0 = no band at all (user 2026-11-04: the gold band went).
    if (bottomHeight > 0) {
      final band = Rect.fromLTWH(0, h - bottomHeight, w, bottomHeight);
      canvas.drawRect(band, Paint()..color = HudBlocks.stoneDark.withValues(alpha: 0.72));
      final rule = Rect.fromLTWH(0, h - bottomHeight, w, 2);
      canvas.drawRect(rule, Paint()..shader = _goldShader(rule, vertical: true));
      canvas.save();
      canvas.translate(0, h - bottomHeight + 4.2);
      _paintScrollBand(canvas, w, 4.4);
      canvas.restore();
    }
    // Corner flourishes: top two under the header, bottom two above the band.
    final path = _flourish().transform(Matrix4.diagonal3Values(1.7, 1.7, 1).storage);
    void corner(double x, double y, double sx, double sy) {
      canvas.save();
      canvas.translate(x, y);
      canvas.scale(sx, sy);
      canvas.drawPath(path.shift(const Offset(0.4, 0.8)), Paint()..color = Colors.black.withValues(alpha: 0.4));
      canvas.drawPath(path, Paint()..shader = _goldShader(const Rect.fromLTWH(0, 0, 24, 24)));
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..color = _kGoldDark,
      );
      canvas.restore();
    }
    corner(1, top + 1, 1, 1);
    corner(w - 1, top + 1, -1, 1);
    corner(1, h - bottomHeight - 1, 1, -1);
    corner(w - 1, h - bottomHeight - 1, -1, -1);
  }

  @override
  bool shouldRepaint(covariant _FiligreeFramePainter old) =>
      old.top != top || old.bottomHeight != bottomHeight;
}
