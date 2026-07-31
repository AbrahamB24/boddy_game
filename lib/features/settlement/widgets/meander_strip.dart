import 'package:flutter/material.dart';

/// A vertical FACET BAND — the ornament that runs down the left and right inside
/// edges of every page (user 2026-07-22, faceted 2026-07-31).
///
/// It was a Greek-key meander: a square spiral hanging off a rail, the ornament
/// of a printed page. The app is low poly now (user: "alles soll im low poly
/// flatdesign sein, so wie dieses Monster"), and the meander's whole character
/// was a STROKE of even weight turning corners — a drawn line, where a faceted
/// world has only filled shapes. This is the same idea in the new language: a
/// column of triangles, alternating which edge they point at, filled with the
/// one tone.
///
/// Drawn rather than shipped as an image so it scales with the page: the unit is
/// derived from the strip's WIDTH, and as many whole triangles as fit are
/// centred vertically. A clipped facet reads as a bug, so the leftover always
/// goes to the margins, never into a half-drawn shape.
class MeanderStrip extends StatelessWidget {
  /// Ink of the band. Alpha is the whole styling story here — this is a
  /// decoration, and it must never compete with the text it frames.
  final Color color;

  /// Mirrors the motif horizontally, so the right-hand band is the left one's
  /// reflection and the page reads symmetrically.
  final bool flip;

  const MeanderStrip({super.key, required this.color, this.flip = false});

  /// How many whole motifs fit a strip of [width] × [height] — 0 when not even
  /// one does. THE rule that keeps a clipped facet off the screen; the painter
  /// draws exactly this many and turns the leftover into margin.
  static int repeatCount(double width, double height) {
    if (width <= 0 || height <= 0) return 0;
    return (height / (width * _FacetPainter.unit)).floor();
  }

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _FacetPainter(color: color, flip: flip));
}

class _FacetPainter extends CustomPainter {
  final Color color;
  final bool flip;

  _FacetPainter({required this.color, required this.flip});

  /// One motif's height, as a multiple of the strip's width. Taller than it is
  /// wide: a squat triangle reads as a chevron pointing sideways, and the band
  /// should read as running DOWN the page.
  static const double unit = 1.6;

  /// The share of the strip's width a triangle spans, so the band keeps air on
  /// both sides and never touches what it frames.
  static const double _inset = 0.16;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;
    final motif = w * unit;
    final n = (h / motif).floor();
    if (n <= 0) return;

    // Centre the whole run: the leftover becomes equal margins top and bottom
    // rather than a partial triangle at the foot.
    final top = (h - n * motif) / 2;
    final left = w * _inset;
    final right = w * (1 - _inset);

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = color
      ..isAntiAlias = true;

    for (var i = 0; i < n; i++) {
      final y = top + i * motif;
      // Alternating: one triangle points at the page, the next at the edge. The
      // PAIR is what makes it a band rather than a row of arrows.
      final pointsIn = i.isEven != flip;
      final path = Path();
      if (pointsIn) {
        path
          ..moveTo(left, y)
          ..lineTo(left, y + motif * 0.72)
          ..lineTo(right, y + motif * 0.36)
          ..close();
      } else {
        path
          ..moveTo(right, y)
          ..lineTo(right, y + motif * 0.72)
          ..lineTo(left, y + motif * 0.36)
          ..close();
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_FacetPainter old) =>
      old.color != color || old.flip != flip;
}
