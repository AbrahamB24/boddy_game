import 'package:flutter/material.dart';

/// A vertical GREEK-KEY BAND — the ornament that runs down the left and right
/// inside edges of every page (user 2026-07-22).
///
/// Back to the ORIGINAL square-spiral meander (user 2026-08-30: "das dreieck
/// mäander durch das ursprüngliche viereckige spiralenmäander ersetzen") — a
/// 2026-07-31 "low poly" pass had swapped it for a column of filled triangles,
/// which read as a row of arrows rather than a meander. This restores the
/// classic shape: a single STROKE of even weight, turning only at right
/// angles, stepping side to side as it runs down the page — a running key
/// pattern, not a spiral coiled into each motif (there is no room to coil at
/// 14px wide), but square-cornered throughout, never curved or pointed.
///
/// Drawn rather than shipped as an image so it scales with the page: the unit
/// is derived from the strip's WIDTH, and as many whole steps fit are centred
/// vertically. A clipped step reads as a bug, so the leftover always goes to
/// the margins, never into a half-drawn turn.
class MeanderStrip extends StatelessWidget {
  /// Ink of the band. Alpha is the whole styling story here — this is a
  /// decoration, and it must never compete with the text it frames.
  final Color color;

  /// Mirrors the motif horizontally, so the right-hand band is the left one's
  /// reflection and the page reads symmetrically.
  final bool flip;

  const MeanderStrip({super.key, required this.color, this.flip = false});

  /// How many whole steps fit a strip of [width] × [height] — 0 when not even
  /// one does. THE rule that keeps a clipped turn off the screen; the painter
  /// draws exactly this many and turns the leftover into margin.
  static int repeatCount(double width, double height) {
    if (width <= 0 || height <= 0) return 0;
    return (height / (width * _KeyPainter.unit)).floor();
  }

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _KeyPainter(color: color, flip: flip));
}

class _KeyPainter extends CustomPainter {
  final Color color;
  final bool flip;

  _KeyPainter({required this.color, required this.flip});

  /// One step's height, as a multiple of the strip's width. Taller than it is
  /// wide, so the band reads as running DOWN the page rather than as a
  /// staircase climbing sideways.
  static const double unit = 1.4;

  /// The two x-positions the line steps between, as a share of the strip's
  /// width — kept off both true edges so the band keeps air on either side.
  static const double _near = 0.22;
  static const double _far = 0.78;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;
    final motif = w * unit;
    final n = (h / motif).floor();
    if (n <= 0) return;

    // Centre the whole run: the leftover becomes equal margins top and bottom
    // rather than a partial step at the foot.
    final top = (h - n * motif) / 2;
    final xA = flip ? w * _far : w * _near;
    final xB = flip ? w * _near : w * _far;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.22
      ..strokeJoin = StrokeJoin.miter
      ..strokeCap = StrokeCap.square
      ..isAntiAlias = true
      ..color = color;

    // ONE continuous path for the whole strip — a square wave, turning only
    // at right angles: straight down, step sideways, straight down, alternating
    // which side each step lands on. That single unbroken line IS the meander;
    // it is what the old doc comment meant by "a stroke of even weight turning
    // corners," just running the strip's full length instead of one motif at a
    // time.
    final path = Path()..moveTo(xA, top);
    var cur = xA;
    for (var i = 0; i < n; i++) {
      final yMid = top + i * motif + motif * 0.5;
      final yEnd = top + (i + 1) * motif;
      final next = cur == xA ? xB : xA;
      path
        ..lineTo(cur, yMid)
        ..lineTo(next, yMid)
        ..lineTo(next, yEnd);
      cur = next;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_KeyPainter old) =>
      old.color != color || old.flip != flip;
}
