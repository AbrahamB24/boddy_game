import 'package:flutter/material.dart';

/// A vertical GREEK-KEY BAND — the ornament that runs down the left and right
/// inside edges of every page (user 2026-07-22).
///
/// TRACED OFF THE REFERENCE, PIXEL FOR PIXEL (user 2026-08-31: "das
/// Mäanderband ist noch nicht identisch mit dem Bild") — the previous
/// redraws (2026-08-30's single-turn spiral, and the plain zigzag before
/// that) were both guesses at the shape from memory. This one is measured: a
/// screenshot of the real key pattern gave a 357×77px strip with a 45px
/// repeat and a 57px cross-section (8..65 after the white margin), on an
/// almost perfectly SQUARE 9px grid both ways. [_coil] is that grid's black
/// region, read off the pixels band by band and merged into rects, with the
/// pattern's own top/bottom bars becoming the two long rails that carry
/// straight through every motif once the strip is turned on its side.
///
/// Drawn rather than shipped as an image so it scales with the page: the unit
/// is derived from the strip's WIDTH, and as many whole motifs fit are
/// centred vertically. A clipped motif reads as a bug, so the leftover always
/// goes to the margins, never into a half-drawn turn.
class MeanderStrip extends StatelessWidget {
  /// Ink of the band. Alpha is the whole styling story here — this is a
  /// decoration, and it must never compete with the text it frames.
  final Color color;

  /// Mirrors the motif horizontally, so the right-hand band is the left one's
  /// reflection and the page reads symmetrically.
  final bool flip;

  /// Runs the rails and the motifs flush to BOTH edges instead of centring
  /// the run with equal margins (user 2026-08-31, the settlement header's
  /// own era panel: "das Band soll oben und unten bis wirklich zur Kante
  /// der Box gehen"). Off everywhere else — a free-floating page edge reads
  /// fine with a small margin; a hard-edged box next to a resource strip
  /// does not. Still never clips a motif: instead of leaving the leftover
  /// as margin, it stretches every motif by the same small amount so a
  /// whole number of them exactly fills the height.
  final bool fillHeight;

  const MeanderStrip({
    super.key,
    required this.color,
    this.flip = false,
    this.fillHeight = false,
  });

  /// How many whole motifs fit a strip of [width] × [height] — 0 when not
  /// even one does. THE rule that keeps a clipped motif off the screen; the
  /// painter draws exactly this many and turns the leftover into margin.
  static int repeatCount(double width, double height) {
    if (width <= 0 || height <= 0) return 0;
    return (height / (width * _KeyPainter.unit)).floor();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _KeyPainter(color: color, flip: flip, fillHeight: fillHeight),
  );
}

class _KeyPainter extends CustomPainter {
  final Color color;
  final bool flip;
  final bool fillHeight;

  _KeyPainter({
    required this.color,
    required this.flip,
    this.fillHeight = false,
  });

  /// One motif's height, as a multiple of the strip's width — the
  /// reference's own ratio (a 45px repeat over a 57px cross-section) rather
  /// than a guessed 1.6.
  static const double unit = 57 / 45;

  /// The reference's TOP and BOTTOM bars, rotated: they ran the full 45px
  /// repeat in the original photo, so here they run the full STRIP HEIGHT
  /// instead of belonging to one motif — the outer rail "carries straight
  /// through," same as the design always intended.
  static const double _leftRailEnd = 0.088;
  static const double _rightRailStart = 0.947;

  /// The coil itself, ONE motif's worth — [x0, x1, y0, y1] fractions, x
  /// across the strip's width, y down this one repeat. Measured off the
  /// reference image band by band (9 horizontal bands at ~9px pitch) and
  /// merged into the minimal rectangle set; nothing here is a round number
  /// because none of the source pixels were.
  static const List<List<double>> _coil = [
    [0.158, 0.246, 0.000, 0.867],
    [0.246, 0.561, 0.000, 0.067],
    [0.561, 0.632, 0.000, 0.089],
    [0.632, 0.702, 0.000, 0.467],
    [0.789, 0.860, 0.000, 0.667],
    [0.316, 0.404, 0.178, 0.667],
    [0.404, 0.474, 0.178, 0.267],
    [0.474, 0.561, 0.178, 0.467],
    [0.561, 0.632, 0.378, 0.467],
    [0.404, 0.789, 0.556, 0.667],
    [0.246, 0.789, 0.778, 0.867],
    [0.789, 0.860, 0.778, 1.000],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;
    final nominal = w * unit;
    final n = fillHeight
        ? (h / nominal).round().clamp(1, 1 << 30)
        : (h / nominal).floor();
    if (n <= 0) return;
    // fillHeight stretches each motif so n of them land EXACTLY on h — no
    // margin, no clipped turn. Otherwise the leftover is split into equal
    // margins top and bottom.
    final motif = fillHeight ? h / n : nominal;
    final top = fillHeight ? 0.0 : (h - n * motif) / 2;
    final bottom = top + n * motif;

    // Mirrored via [flip] — the SAME fractions, read right-to-left instead of
    // left-to-right, rather than a second, hand-measured copy.
    double gx(double frac) => flip ? w * (1 - frac) : w * frac;
    (double, double) xr(double f0, double f1) {
      final a = gx(f0), b = gx(f1);
      return a < b ? (a, b) : (b, a);
    }

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..color = color;

    final left = xr(0, _leftRailEnd);
    canvas.drawRect(Rect.fromLTRB(left.$1, top, left.$2, bottom), paint);
    final right = xr(_rightRailStart, 1);
    canvas.drawRect(Rect.fromLTRB(right.$1, top, right.$2, bottom), paint);

    for (var i = 0; i < n; i++) {
      final motifTop = top + i * motif;
      for (final r in _coil) {
        final x = xr(r[0], r[1]);
        canvas.drawRect(
          Rect.fromLTRB(
            x.$1,
            motifTop + r[2] * motif,
            x.$2,
            motifTop + r[3] * motif,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_KeyPainter old) =>
      old.color != color || old.flip != flip || old.fillHeight != fillHeight;
}
