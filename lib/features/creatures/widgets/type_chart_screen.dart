import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/cream_kit.dart';
import '../../../core/theme/foe_theme.dart';
import '../../../core/ui/pressable.dart';
import '../models/creature_enums.dart';

/// THE TYPE CHART — "Ring, auswählbar" (user 2026-09-22, replacing the German
/// "Typen-Kreis" dialog): the ring of six types with Light and Shadow inside it,
/// but with the arrows of ONE type at a time. Every arrow at once was a tangle;
/// with a type picked, green arrows leave it (what it hits hard) and red arrows
/// arrive (what hits it hard), everything else fades to a faint web. The card on
/// the right says the same in words, with the multiplier next to each name.
///
/// Every number is [CreatureElement.multiplierVs] itself — the diagram draws no
/// value of its own, so it cannot disagree with the fight.
Future<void> showTypeChart(BuildContext context, {CreatureElement? initial}) =>
    pushMenu(context, TypeChartScreen(initial: initial));

/// The eight real types, in the order the ring and the matrix use.
final List<CreatureElement> kChartTypes = [
  for (final e in CreatureElement.values)
    if (e != CreatureElement.neutral) e,
];

/// What [type] hits for more than ×1, strongest first.
List<CreatureElement> typesHitHard(CreatureElement type) => _sorted(
  kChartTypes.where((o) => type.multiplierVs(o) > 1),
  (o) => type.multiplierVs(o),
);

/// What [type] hits for less than ×1, mildest first.
List<CreatureElement> typesHitWeak(CreatureElement type) => _sorted(
  kChartTypes.where((o) => type.multiplierVs(o) < 1),
  (o) => type.multiplierVs(o),
);

/// What hits [type] for more than ×1, strongest first.
List<CreatureElement> typesHittingHard(CreatureElement type) => _sorted(
  kChartTypes.where((o) => o.multiplierVs(type) > 1),
  (o) => o.multiplierVs(type),
);

List<CreatureElement> _sorted(
  Iterable<CreatureElement> types,
  double Function(CreatureElement) by,
) => types.toList()
  ..sort((a, b) {
    final c = by(b).compareTo(by(a));
    return c != 0 ? c : a.index.compareTo(b.index);
  });

class TypeChartScreen extends StatefulWidget {
  /// The type selected when the page opens — in a fight, the enemy's own.
  final CreatureElement? initial;
  const TypeChartScreen({super.key, this.initial});

  @override
  State<TypeChartScreen> createState() => _TypeChartScreenState();
}

class _TypeChartScreenState extends State<TypeChartScreen> {
  late CreatureElement _sel =
      widget.initial == null || widget.initial == CreatureElement.neutral
      ? CreatureElement.fire
      : widget.initial!;

  @override
  Widget build(BuildContext context) => MenuScaffold(
    title: '🛡 Type chart',
    trailing: Text(
      'tap a type · green hits, red is hit',
      style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 392,
          child: creamCard(
            padding: const EdgeInsets.all(6),
            child: _Ring(
              selected: _sel,
              onPick: (e) => setState(() => _sel = e),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: _InfoCard(type: _sel)),
      ],
    ),
  );
}

// ── Multiplier colours: one set for the arrows, the pills and the legend ─────
const Color _kGreen = Color(0xFF1F8A4C);
const Color _kRed = Color(0xFFC0432B);

(Color bg, Color fg) _multColors(double v) {
  if (v >= 1.5) return (_kGreen, Colors.white);
  if (v > 1) return (const Color(0xFF8CCB63), const Color(0xFF16320C));
  if (v < 0.75) return (_kRed, Colors.white);
  if (v < 1) return (const Color(0xFFEBA55A), const Color(0xFF3A1F04));
  return (kBoxInk.withValues(alpha: 0.10), kBoxInkSoft);
}

String _mult(double v) => '×${v % 1 == 0 ? v.toInt() : v}';

/// What the game calls a multiplier.
String _word(double v) => switch (v) {
  >= 1.5 => 'Super effective',
  > 1 => 'Effective',
  >= 1 => 'Normal',
  >= 0.75 => 'Resisted',
  _ => 'Very resisted',
};

/// The element's round badge — its colour, the same dark rim the type icon and
/// the monster shadows use, and the emoji.
Widget _badge(CreatureElement e, double size) => Container(
  width: size,
  height: size,
  alignment: Alignment.center,
  decoration: BoxDecoration(
    shape: BoxShape.circle,
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color.lerp(e.color, Colors.white, 0.28)!, e.color],
    ),
    boxShadow: [BoxShadow(color: e.shadowColor, offset: const Offset(0, 2))],
  ),
  child: Text(e.emoji, style: TextStyle(fontSize: size * 0.56, height: 1)),
);

// ── The ring ─────────────────────────────────────────────────────────────────
/// Design space of the diagram; a [FittedBox] scales it into its card.
const Size _kDesign = Size(360, 340);
const Offset _kCentre = Offset(180, 170);
const double _kRingRadius = 128;
const double _kHubOffset = 38;

/// Where a type sits: the first six round the ring (Fire on top, clockwise, the
/// order they beat each other in), Light and Shadow inside it.
Offset _nodePos(CreatureElement e) {
  final i = kChartTypes.indexOf(e);
  if (i < 6) {
    const angles = [-90.0, -30.0, 30.0, 90.0, 150.0, 210.0];
    final a = angles[i] * math.pi / 180;
    return _kCentre + Offset(math.cos(a), math.sin(a)) * _kRingRadius;
  }
  return _kCentre + Offset(i == 6 ? -_kHubOffset : _kHubOffset, 0);
}

double _nodeRadius(CreatureElement e) => kChartTypes.indexOf(e) < 6 ? 22 : 19;

class _Ring extends StatelessWidget {
  final CreatureElement selected;
  final ValueChanged<CreatureElement> onPick;
  const _Ring({required this.selected, required this.onPick});

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.contain,
    child: SizedBox.fromSize(
      size: _kDesign,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _ArrowPainter(selected, kBoxInk)),
          ),
          for (final e in kChartTypes) _node(e),
        ],
      ),
    ),
  );

  Widget _node(CreatureElement e) {
    final pos = _nodePos(e);
    final r = _nodeRadius(e);
    final on = e == selected;
    final d = (r + (on ? 5 : 0)) * 2;
    return Positioned(
      left: pos.dx - d / 2,
      top: pos.dy - d / 2,
      width: d,
      height: d,
      child: Pressable(
        onTap: () => onPick(e),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? CreamPalette.gold : null,
          ),
          child: Container(
            width: r * 2,
            height: r * 2,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: e.color,
              border: Border.all(color: e.shadowColor, width: 2.5),
            ),
            child: Text(
              e.emoji,
              style: TextStyle(fontSize: r < 20 ? 16 : 19, height: 1),
            ),
          ),
        ),
      ),
    );
  }
}

/// The arrows. For the selected type: green out to everything it hits harder
/// than ×1, red in from everything that hits it harder than ×1. Every other
/// advantage is a barely-there line, so the ring's structure still shows.
/// Each arrow bows a little to its right, so the two arrows of a pair that beat
/// each other (Light and Shadow) do not lie on top of one another.
class _ArrowPainter extends CustomPainter {
  final CreatureElement selected;
  final Color ink;
  const _ArrowPainter(this.selected, this.ink);

  @override
  void paint(Canvas canvas, Size size) {
    void arrow(
      CreatureElement a,
      CreatureElement b,
      Color color,
      double width, {
      bool head = true,
    }) {
      final p1 = _nodePos(a), p2 = _nodePos(b);
      final d = p2 - p1;
      final len = d.distance;
      final u = d / len;
      final n = Offset(-u.dy, u.dx);
      final start = p1 + u * (_nodeRadius(a) + 2);
      final end = p2 - u * (_nodeRadius(b) + 5);
      final ctrl = (start + end) / 2 + n * 14;
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(
        Path()
          ..moveTo(start.dx, start.dy)
          ..quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy),
        paint,
      );
      if (!head) return;
      final t = end - ctrl;
      final tu = t / t.distance;
      final tn = Offset(-tu.dy, tu.dx);
      canvas.drawPath(
        Path()
          ..moveTo(end.dx + tu.dx * 4, end.dy + tu.dy * 4)
          ..lineTo(
            end.dx - tu.dx * 9 + tn.dx * 6,
            end.dy - tu.dy * 9 + tn.dy * 6,
          )
          ..lineTo(
            end.dx - tu.dx * 9 - tn.dx * 6,
            end.dy - tu.dy * 9 - tn.dy * 6,
          )
          ..close(),
        Paint()..color = color,
      );
    }

    // The web first, then the selected type's arrows over it.
    final web = ink.withValues(alpha: 0.09);
    for (final a in kChartTypes) {
      for (final b in kChartTypes) {
        if (a == b || a.multiplierVs(b) <= 1) continue;
        if (a == selected || b == selected) continue;
        arrow(a, b, web, 1, head: false);
      }
    }
    for (final b in kChartTypes) {
      final out = selected.multiplierVs(b);
      if (b != selected && out > 1) {
        arrow(selected, b, _kGreen, out >= 1.5 ? 3.6 : 2);
      }
      final into = b.multiplierVs(selected);
      if (b != selected && into > 1) {
        arrow(b, selected, _kRed, into >= 1.5 ? 3.6 : 2);
      }
    }
  }

  @override
  bool shouldRepaint(_ArrowPainter old) =>
      old.selected != selected || old.ink != ink;
}

// ── The words ────────────────────────────────────────────────────────────────
class _InfoCard extends StatelessWidget {
  final CreatureElement type;
  const _InfoCard({required this.type});

  @override
  Widget build(BuildContext context) => creamCard(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _badge(type, 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.label,
                      style: FoE.value(size: 22).copyWith(color: kBoxInk),
                    ),
                    Text(
                      'tap a type in the ring',
                      style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _section(
            'Hits hard',
            _kGreen,
            typesHitHard(type),
            (o) => type.multiplierVs(o),
          ),
          _section(
            'Hits weak',
            const Color(0xFFEBA55A),
            typesHitWeak(type),
            (o) => type.multiplierVs(o),
          ),
          _section(
            'Is hit hard by',
            _kRed,
            typesHittingHard(type),
            (o) => o.multiplierVs(type),
          ),
          const SizedBox(height: 2),
          Text(
            'Green arrow: ${type.label} → target. Red arrow: attacker → '
            '${type.label}. Thick = ×1.5, thin = ×1.25. Everything not listed '
            'is ×1.',
            style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft, height: 1.3),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 5,
            children: [
              for (final v in const [1.5, 1.25, 0.75, 0.5]) _legend(v),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _section(
    String label,
    Color dot,
    List<CreatureElement> types,
    double Function(CreatureElement) value,
  ) {
    if (types.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: dot,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: kBoxAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 6,
            runSpacing: 5,
            children: [for (final o in types) _pill(o, value(o))],
          ),
        ],
      ),
    );
  }

  Widget _pill(CreatureElement e, double v) {
    final (bg, fg) = _multColors(v);
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 3, 8, 3),
      decoration: raisedTile(radius: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _badge(e, 20),
          const SizedBox(width: 5),
          Text(e.label, style: FoE.label(size: 12).copyWith(color: kBoxInk)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              _mult(v),
              style: FoE.value(size: 11).copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(double v) {
    final (bg, fg) = _multColors(v);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(_mult(v), style: FoE.value(size: 10).copyWith(color: fg)),
        ),
        const SizedBox(width: 5),
        Text(_word(v), style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft)),
      ],
    );
  }
}
