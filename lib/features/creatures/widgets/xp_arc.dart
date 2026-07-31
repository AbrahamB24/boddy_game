import 'dart:math' as math;

import 'package:flutter/material.dart';


/// The XP indicator drawn as an open-topped semicircle "bowl" that sits under a
/// monster's feet: a bright amber fill growing from the upper-left, along the
/// bottom, to the upper-right, with a dot at the leading edge and the rest left
/// as a pale track — the same fill language as the leading-dot bars.
///
/// Shared by the creature DETAIL screen and the collection CARD (user
/// 2026-07-24) so the EP indicator reads identically in both.
class XpArcPainter extends CustomPainter {
  final double frac;
  final double stroke;
  final double dotRadius;

  const XpArcPainter(this.frac, {this.stroke = 3.0, this.dotRadius = 4.0});

  // ── Reading on ANY backdrop (user 2026-07-27: "nun muss der EP Balken
  // besser erkennbar sein farblich") ──────────────────────────────────────
  //
  // The arc was FoE.gold (#9A6A18) on a white-at-22% track. That is the app's
  // burnt amber, picked to read as ink ON PAPER — and this arc is never on
  // paper. It sits at the seam of a tile that is now one saturated ELEMENT
  // colour, so on fire it was amber on orange and on a legendary it was amber
  // on gold: the same hue, a shade apart.
  //
  // Two changes. The fill is a BRIGHT amber that no element colour reaches, and
  // the whole arc is drawn over a dark CASING first — a slightly wider stroke
  // in translucent black. The casing is what makes it work everywhere: against
  // a light element it is the outline that holds the shape, against a dark one
  // it disappears into the background and costs nothing.
  static const _fill = Color(0xFFFFC53D);
  static const _casing = Color(0x59000000); // black @ 0.35
  // Sweep from the upper-left tip (195°) clockwise down through the bottom (90°)
  // to the upper-right tip (-15°): 210° of an ellipse, opening at the top.
  static const _start = 195 * math.pi / 180;
  static const _sweep = -210 * math.pi / 180;
  // white @ 0.30 — a const value (withValues can't be const). The unearned part
  // of the arc: brighter than it was, so "how far along am I" is a comparison
  // between two visible things rather than one.
  static const _track = Color(0x4DFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke + 1);
    Paint arc(Color color, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width
      ..color = color;

    // The casing, under everything — the arc's own shadow, so neither the
    // track nor the fill has to survive on contrast with the tile alone.
    canvas.drawArc(rect, _start, _sweep, false, arc(_casing, stroke + 2));
    canvas.drawArc(rect, _start, _sweep, false, arc(_track, stroke));

    final f = frac.clamp(0.0, 1.0);
    if (f > 0) {
      canvas.drawArc(rect, _start, _sweep * f, false, arc(_fill, stroke));
    }

    // Dot at the leading edge, on the SAME ellipse the arc was drawn on — with
    // its own dark rim, for the same reason the arc has a casing.
    final ang = _start + _sweep * f;
    final c = rect.center;
    final pos = Offset(
      c.dx + rect.width / 2 * math.cos(ang),
      c.dy + rect.height / 2 * math.sin(ang),
    );
    canvas.drawCircle(pos, dotRadius + 1, Paint()..color = _casing);
    canvas.drawCircle(pos, dotRadius, Paint()..color = _fill);
  }

  @override
  bool shouldRepaint(XpArcPainter old) =>
      old.frac != frac || old.stroke != stroke || old.dotRadius != dotRadius;
}
