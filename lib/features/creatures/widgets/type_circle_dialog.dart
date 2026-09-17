import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../../common/widgets/parchment_page.dart';

/// The live type chart (user 2026-09-07, moved from an inline battle-screen
/// strip into its own overlay: "das müsste viel grösser sein und alle
/// Verbindungen eingezeichnet... mache bitte ein Overlaymenü wie der
/// Buildingdetailscreen"; the 8-type redesign it charted went live in
/// [CreatureElement] on 2026-09-08). Every value drawn here is exactly
/// [CreatureElement.multiplierVs]'s own matrix — see that class's doc for
/// the ring/hub derivation this diagram visualises.
Future<void> showTypeCircleDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => ParchmentDialog(
    title: 'Typen-Kreis',
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: CustomPaint(
              painter: const _TypeCirclePainter(),
              child: const _TypeCircleLabels(),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Feuer→Eis→Pflanze→Blitz→Wasser→Stein→Feuer: Pfeil = wer im '
            'Vorteil ist, Zahl = Schadens-Multiplikator. Licht und Schatten '
            'sitzen in der Mitte mit je eigenen Werten gegen jeden Typ, '
            'plus ihrer eigenen 1.5-Rivalität. Beide sind zusätzlich gegen '
            'sich selbst geschwächt (×0.5) — die 6 Ring-Typen sind es gegen '
            'sich selbst nicht (×1.0).',
            textAlign: TextAlign.center,
            style: FoE.dim(size: 11),
          ),
        ],
      ),
    ),
  ),
);

/// One ring type's emoji and angle (degrees, canvas convention: 0°=right,
/// 90°=down). Order matches the cycle Feuer→Eis→Pflanze→Blitz→Wasser→Stein.
/// No per-type colour any more (user 2026-09-07: edges are coloured by
/// bonus/malus now, not by type/hub — see _TypeCirclePainter).
const List<(String emoji, double angleDeg)> _kRingNodes = [
  ('🔥', -90), // Feuer
  ('🧊', -30), // Eis
  ('🌿', 30), // Pflanze
  ('⚡', 90), // Blitz
  ('💧', 150), // Wasser
  ('🪨', 210), // Stein
];

/// One directed "X beats Y" edge, or a neutral (undirected) pair when
/// [value] == 1.0. [arc] true draws it as a bow following the ring's own
/// circumference (ring↔ring only); false draws a straight line (anything
/// touching a hub, or a ring↔ring neutral opposite pair — a straight chord
/// reads better than an arc for those since they aren't adjacent on the
/// ring).
class _Edge {
  final int from; // index into _kRingNodes, or -1/-2 for Licht/Schatten
  final int to;
  final double value;
  final bool arc;
  const _Edge(this.from, this.to, this.value, {this.arc = false});
}

const int _kLicht = -1;
const int _kSchatten = -2;

/// All 28 pairs among the 8 types (see the design chat this codifies):
/// 15 ring↔ring, 12 hub↔ring, 1 hub↔hub. A neutral pair (value 1.0) has no
/// real attacker — drawn as a plain line, no arrowhead.
const List<_Edge> _kEdges = [
  // Ring, 1 step clockwise: the mild ×1.25 advantage.
  _Edge(0, 1, 1.25, arc: true), // Feuer → Eis
  _Edge(1, 2, 1.25, arc: true), // Eis → Pflanze
  _Edge(2, 3, 1.25, arc: true), // Pflanze → Blitz
  _Edge(3, 4, 1.25, arc: true), // Blitz → Wasser
  _Edge(4, 5, 1.25, arc: true), // Wasser → Stein
  _Edge(5, 0, 1.25, arc: true), // Stein → Feuer
  // Ring, 2 steps clockwise: the strong ×1.5 advantage.
  _Edge(0, 2, 1.5, arc: true), // Feuer → Pflanze
  _Edge(1, 3, 1.5, arc: true), // Eis → Blitz
  _Edge(2, 4, 1.5, arc: true), // Pflanze → Wasser
  _Edge(3, 5, 1.5, arc: true), // Blitz → Stein
  _Edge(4, 0, 1.5, arc: true), // Wasser → Feuer
  _Edge(5, 1, 1.5, arc: true), // Stein → Eis
  // Ring, opposite (3 steps): neutral.
  _Edge(0, 3, 1.0), // Feuer ↔ Blitz
  _Edge(1, 4, 1.0), // Eis ↔ Wasser
  _Edge(2, 5, 1.0), // Pflanze ↔ Stein
  // Licht vs. every ring type.
  _Edge(_kLicht, 0, 1.0), // ↔ Feuer, neutral
  _Edge(_kLicht, 1, 1.25), // → Eis
  _Edge(_kLicht, 2, 1.5), // → Pflanze
  _Edge(3, _kLicht, 1.25), // Blitz →
  _Edge(4, _kLicht, 1.25), // Wasser →
  _Edge(5, _kLicht, 1.5), // Stein →
  // Schatten vs. every ring type.
  _Edge(0, _kSchatten, 1.25), // Feuer →
  _Edge(_kSchatten, 1, 1.0), // ↔ Eis, neutral
  _Edge(2, _kSchatten, 1.25), // Pflanze →
  _Edge(_kSchatten, 3, 1.25), // → Blitz
  _Edge(_kSchatten, 4, 1.25), // → Wasser
  _Edge(_kSchatten, 5, 1.5), // → Stein
];

class _TypeCirclePainter extends CustomPainter {
  const _TypeCirclePainter();

  static const double _d2r = math.pi / 180;
  static const double _ringFraction = 0.82;
  static const double _hubOffsetFraction = 0.16;

  // Green bonus / coral malus (user 2026-09-07: "Grün bonus, koralle Malus")
  // — every real (non-neutral) arrow's line is the BONUS colour (it's a real
  // advantage for whoever it starts at) and its arrowhead is the MALUS
  // colour (that's where the extra damage actually lands). NOT FoE.positive
  // for the bonus — that name predates the 2026-09-05 reskin and is actually
  // this app's cyan-blue accent now, not green (see foe_theme.dart), so a
  // real green is picked here instead. FoE.danger already IS coral.
  static const Color _bonus = Color(0xFF3BAE78);
  static const Color _malus = FoE.danger;
  static const Color _neutral = FoE.textDim;

  Offset _ringPos(Offset c, double r, double angleDeg) =>
      c + Offset(math.cos(angleDeg * _d2r), math.sin(angleDeg * _d2r)) * r;

  /// Node CENTRE for [i] (ring index 0..5, or [_kLicht]/[_kSchatten]).
  Offset _nodePos(Offset c, double r, int i) {
    if (i == _kLicht) return c - Offset(0, r * _hubOffsetFraction);
    if (i == _kSchatten) return c + Offset(0, r * _hubOffsetFraction);
    return _ringPos(c, r, _kRingNodes[i].$2);
  }

  static Offset _rotate(Offset v, double a) {
    final cs = math.cos(a), sn = math.sin(a);
    return Offset(v.dx * cs - v.dy * sn, v.dx * sn + v.dy * cs);
  }

  void _arrowHead(Canvas canvas, Offset tip, Offset fromDir, Paint fill) {
    final dir = fromDir / fromDir.distance;
    const head = 8.0;
    final back = -dir;
    final p1 = tip + _rotate(back, 0.45) * head;
    final p2 = tip + _rotate(back, -0.45) * head;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close(),
      fill,
    );
  }

  void _label(Canvas canvas, Offset pos, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: FoE.parchment,
          backgroundColor: FoE.bg.withValues(alpha: 0.8),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  /// Pulls [p] a few px toward [towards] — so a line/curve stops just short
  /// of the node instead of running under the emoji.
  Offset _shorten(Offset p, Offset towards, double by) {
    final d = towards - p;
    final len = d.distance;
    return len <= by ? p : p + d / len * by;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2 * _ringFraction;

    for (final e in _kEdges) {
      final neutral = e.value == 1.0;
      final isHub = e.from < 0 || e.to < 0;
      final lineColor = neutral ? _neutral : _bonus;
      final headColor = neutral ? _neutral : _malus;
      final width = neutral
          ? 1.0
          : e.value >= 1.5
          ? 2.4
          : 1.7;
      final stroke = Paint()
        ..color = lineColor.withValues(alpha: neutral ? 0.4 : 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round;
      final headFill = Paint()..color = headColor.withValues(alpha: 0.9);

      final fromPos = _nodePos(c, r, e.from);
      final toPos = _nodePos(c, r, e.to);
      final fromShort = _shorten(fromPos, toPos, isHub ? 20 : 14);
      final toShort = _shorten(toPos, fromPos, isHub ? 20 : 14);

      if (e.arc && !isHub) {
        // Ring↔ring, 1 or 2 steps apart: a BOW between the two node centres
        // (user 2026-09-07: "keinen kompletten Kreis bilden, sondern
        // wirklich Pfeile") — NOT an arc traced along the ring's own
        // circumference. That was the earlier bug: 6 arcs of 120° each
        // cover 720° of a 360° ring, so they double back over each other
        // and the whole thing reads as one solid circle with barely-visible
        // arrowheads, not 6 distinct arrows. A quadratic bow with its
        // control point pushed OUTWARD (2-step pushed further than 1-step,
        // so the two tiers don't sit on the same curve either) draws each
        // relationship as its own separate, readable arrow.
        final chordMid = Offset.lerp(fromPos, toPos, 0.5)!;
        final outward = (chordMid - c);
        final outwardUnit = outward.distance > 0
            ? outward / outward.distance
            : const Offset(0, -1);
        final bow = r * (e.value >= 1.5 ? 0.34 : 0.16);
        final control = chordMid + outwardUnit * bow;
        final path = Path()
          ..moveTo(fromShort.dx, fromShort.dy)
          ..quadraticBezierTo(control.dx, control.dy, toShort.dx, toShort.dy);
        canvas.drawPath(path, stroke);
        // Tangent at the END of a quadratic bezier points from the control
        // point to the endpoint.
        _arrowHead(canvas, toShort, toShort - control, headFill);
        _label(canvas, control, e.value.toString());
      } else if (neutral) {
        // A ring↔ring OPPOSITE pair, or a hub↔ring pair that happens to be
        // neutral: a plain dashed line, no arrowhead (nobody's favoured).
        canvas.drawPath(
          _dashed(
            Path()
              ..moveTo(fromShort.dx, fromShort.dy)
              ..lineTo(toShort.dx, toShort.dy),
            5,
            4,
          ),
          stroke,
        );
        _label(canvas, Offset.lerp(fromShort, toShort, 0.5)!, '1.0');
      } else {
        // Hub↔ring: a straight line (Licht/Schatten sit near the centre, so
        // every one of their 6 ties is already visually distinct — no ring
        // arc trick needed here).
        canvas.drawLine(fromShort, toShort, stroke);
        _arrowHead(canvas, toShort, toShort - fromShort, headFill);
        // Nearer the ring end, away from the crowded centre.
        _label(canvas, Offset.lerp(fromPos, toPos, 0.7)!, e.value.toString());
      }
    }

    // The hub↔hub mutual rivalry: BOTH directions are a real advantage
    // (×1.5 each way), so both ends get a malus arrowhead.
    final lichtPos = _nodePos(c, r, _kLicht);
    final schattenPos = _nodePos(c, r, _kSchatten);
    final lichtShort = _shorten(lichtPos, schattenPos, 16);
    final schattenShort = _shorten(schattenPos, lichtPos, 16);
    final mutualStroke = Paint()
      ..color = _bonus.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final mutualHead = Paint()..color = _malus.withValues(alpha: 0.9);
    canvas.drawLine(lichtShort, schattenShort, mutualStroke);
    _arrowHead(canvas, schattenShort, schattenShort - lichtShort, mutualHead);
    _arrowHead(canvas, lichtShort, lichtShort - schattenShort, mutualHead);
    _label(canvas, Offset.lerp(lichtPos, schattenPos, 0.5)!, '1.5');
  }

  /// A dashed version of [source] (Flutter's Canvas has no dash support
  /// built in) — used for the neutral (no real advantage) pairs so they
  /// read as visually lighter than a real "beats" arrow.
  Path _dashed(Path source, double dashLen, double gapLen) {
    final dashed = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      var draw = true;
      while (distance < metric.length) {
        final next = distance + (draw ? dashLen : gapLen);
        if (draw) {
          dashed.addPath(
            metric.extractPath(distance, math.min(next, metric.length)),
            Offset.zero,
          );
        }
        distance = next;
        draw = !draw;
      }
    }
    return dashed;
  }

  @override
  bool shouldRepaint(_TypeCirclePainter old) => false;
}

class _TypeCircleLabels extends StatelessWidget {
  const _TypeCircleLabels();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final r = box.biggest.shortestSide / 2 * _TypeCirclePainter._ringFraction;
      final hubOffset =
          box.biggest.shortestSide / 2 * _TypeCirclePainter._hubOffsetFraction;
      // No circle badge behind the emoji any more (user 2026-09-07: "die
      // Kreise um die Icons löschen") — the glyph sits directly on the
      // diagram, same as the pre-existing fire/water/plant chart did.
      Widget node(String emoji, Offset centerOffset) => Positioned(
        left: box.maxWidth / 2 + centerOffset.dx - 16,
        top: box.maxHeight / 2 + centerOffset.dy - 16,
        width: 32,
        height: 32,
        child: Center(
          child: Text(emoji, style: const TextStyle(fontSize: 22)),
        ),
      );
      return Stack(
        children: [
          for (final n in _kRingNodes)
            node(
              n.$1,
              Offset(
                math.cos(n.$2 * math.pi / 180),
                math.sin(n.$2 * math.pi / 180),
              ) * r,
            ),
          node('✨', Offset(0, -hubOffset)),
          node('🌑', Offset(0, hubOffset)),
        ],
      );
    },
  );
}
