import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';

// ── Signs of life on a still picture (user 2026-08-04) ─────
// "Zudem bitte kleinere Animationen hinzufügen wie Licht, Rauch, Wind etc., so
// dass etwas Leben hineinkommt."
//
// The buildings are single PNGs; the map draws them and nothing about them
// moves. Animating what is INSIDE the picture — a banner in the wind, grass
// bending — would mean rendering a frame sequence per building and playing it,
// which is a different and much larger piece of work.
//
// What can move is what a building EMITS, and that turns out to be most of the
// effect anyway: smoke leaving a chimney and light spilling out of windows are
// both things that happen in front of the wall rather than on it. Two small
// painters, no new art, and they work for a Gemini render exactly as well as
// for a Blender one.
//
// ── The rules both of them keep ──
//  * Slow. A settlement is a place, not a screensaver — anything you notice
//    moving twice is too fast.
//  * Cheap. RepaintBoundary around each, no rebuild of the tile behind them,
//    and nothing at all when the building is unfinished or paused.
//  * Phase-shifted per building, so a row of houses never puffs in unison.
//    That is the single tell that separates "a village" from "a tilemap".

/// Smoke leaving a chimney: a few puffs rising, spreading and fading out.
class ChimneySmoke extends StatefulWidget {
  /// Where the chimney mouth is, in fractions of this box.
  final double anchorX;
  final double anchorY;

  /// Distinct per building so neighbours are out of step. Any stable number
  /// does — the map passes the placed building's id hash.
  final int phaseSeed;

  const ChimneySmoke({
    super.key,
    required this.anchorX,
    required this.anchorY,
    required this.phaseSeed,
  });

  @override
  State<ChimneySmoke> createState() => _ChimneySmokeState();
}

class _ChimneySmokeState extends State<ChimneySmoke>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    // Six seconds for one puff's whole life. Slower than it sounds: with four
    // puffs staggered across it, one leaves the chimney every second and a half.
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _SmokePainter(
            t: _c.value,
            anchorX: widget.anchorX,
            anchorY: widget.anchorY,
            seed: widget.phaseSeed,
          ),
          size: Size.infinite,
        ),
      ),
    ),
  );
}

class _SmokePainter extends CustomPainter {
  final double t;
  final double anchorX;
  final double anchorY;
  final int seed;

  static const int _puffs = 4;

  const _SmokePainter({
    required this.t,
    required this.anchorX,
    required this.anchorY,
    required this.seed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final ox = size.width * anchorX;
    final oy = size.height * anchorY;
    // The rise is measured against the building's own WIDTH, so smoke is the
    // same size relative to a 1x1 hut as to a 5x5 hall. Against height it would
    // scale with how tall the picture happens to be, which is a property of the
    // roof rather than of the fire.
    final rise = size.width * 0.42;
    final drift = size.width * 0.13;

    for (var i = 0; i < _puffs; i++) {
      // Each puff is the same life, started at a different point in it.
      final phase = ((t + i / _puffs + (seed % 97) / 97) % 1.0);
      // Eased so a puff leaves briskly and slows as it thins — smoke is fast
      // where it is hot and slow once it is not.
      final e = 1 - math.pow(1 - phase, 1.8).toDouble();
      // Wind: a slow lean that reverses, not a constant drift. A steady slant
      // reads as a fan somewhere off-screen.
      final gust = math.sin((t + (seed % 31) / 31) * math.pi * 2) * 0.5 + 0.6;
      final dx = drift * e * gust + math.sin(phase * 5 + i) * size.width * 0.012;
      final dy = -rise * e;
      final r = size.width * (0.022 + 0.055 * e);
      // Fades in over the first fifth so a puff is never born at full strength
      // in mid air, then out over the rest.
      final a = (phase < 0.2 ? phase / 0.2 : (1 - phase) / 0.8) * 0.34;
      if (a <= 0.01) continue;
      canvas.drawCircle(
        Offset(ox + dx, oy + dy),
        r,
        Paint()
          ..color = FoE.parchment.withValues(alpha: a)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(_SmokePainter old) => old.t != t;
}

/// Lamplight breathing out of a building's lower half.
///
/// Deliberately NOT anchored to each window. It is a soft warm pool low on the
/// sprite, which is where doors and ground-floor windows are on every one of
/// these buildings — so it needs no per-picture measurement and works on art
/// that arrived from a prompt. A per-window glow would need a list of points
/// per building and would look wrong the moment one was off by a few pixels.
class LampGlow extends StatefulWidget {
  final int phaseSeed;

  const LampGlow({super.key, required this.phaseSeed});

  @override
  State<LampGlow> createState() => _LampGlowState();
}

class _LampGlowState extends State<LampGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          // A slow breath with a small irregular tremor on top: a pure sine
          // reads as a pulsing UI element, and a flame does not keep time.
          final base = Curves.easeInOut.transform(_c.value);
          final tremor =
              math.sin((_c.value + widget.phaseSeed % 13 / 13) * 17) * 0.12;
          final a = (0.10 + base * 0.09 + tremor * 0.03).clamp(0.0, 0.3);
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, 0.62),
                radius: 0.55,
                colors: [
                  FoE.goldBright.withValues(alpha: a),
                  FoE.goldBright.withValues(alpha: 0),
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          );
        },
      ),
    ),
  );
}
