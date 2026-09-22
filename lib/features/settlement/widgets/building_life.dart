import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';

/// ONE slow clock for every ambient effect on the map (2026-09-20).
///
/// Each smoke stack and lamp glow used to own an AnimationController running
/// at the display's full refresh rate, forever — with a village of a hundred
/// buildings that is a hundred tickers, a hundred layers re-recorded and
/// re-rasterised sixty times a second (the smoke also drew four blurred
/// circles per frame each), and a frame scheduled every vsync so the device
/// never idled. The effects are deliberately slow (a puff lives six seconds),
/// so ~11 updates a second is indistinguishable to the eye and costs a
/// fraction of that.
///
/// It only ticks while at least one effect is mounted AND on screen: a
/// [Timer] rather than a Ticker so it schedules a frame only when it fires,
/// stopped when the app is backgrounded and by [TickerMode] when the map is
/// covered by another route.
class AmbientClock extends ChangeNotifier with WidgetsBindingObserver {
  AmbientClock._();

  static final AmbientClock instance = AmbientClock._();

  /// Time between updates. 90 ms ≈ 11 Hz.
  static const Duration period = Duration(milliseconds: 90);

  final Stopwatch _watch = Stopwatch()..start();
  Timer? _timer;
  int _users = 0;
  bool _observing = false;
  bool _foreground = true;

  @visibleForTesting
  bool get isRunning => _timer != null;

  /// Seconds since the clock was created — the phase every effect reads.
  double get seconds => _watch.elapsedMicroseconds / 1e6;

  /// An effect came on screen. Pair with [release].
  void retain() {
    _users++;
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
    _sync();
  }

  void release() {
    if (_users > 0) _users--;
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground =
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden &&
        state != AppLifecycleState.detached;
    _sync();
  }

  void _sync() {
    final want = _users > 0 && _foreground;
    if (want && _timer == null) {
      _timer = Timer.periodic(period, (_) => notifyListeners());
    } else if (!want && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }
}

/// Keeps [AmbientClock] running for as long as the widget is mounted and its
/// route is the visible one.
mixin _AmbientClockUser<T extends StatefulWidget> on State<T> {
  bool _retained = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_retained) {
      _retained = true;
      AmbientClock.instance.retain();
    } else if (!visible && _retained) {
      _retained = false;
      AmbientClock.instance.release();
    }
  }

  @override
  void dispose() {
    if (_retained) {
      _retained = false;
      AmbientClock.instance.release();
    }
    super.dispose();
  }
}

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

/// ONE LAYER PER BUILDING (2026-09-21).
///
/// The lamplight and the smoke used to be two separate widgets stacked on
/// each building: two [AmbientClock] listeners, two [RepaintBoundary] layers
/// — so two composited textures and two rebuilds — for every lit house on
/// the map. A village of a hundred paid that a hundred times over, eleven
/// times a second. They occupy the same box and share the same clock, so
/// they are one painter now: one listener, one layer, one repaint.
///
/// The glow also stopped being a [DecoratedBox]. Rebuilding one meant a
/// fresh `BoxDecoration` and a fresh `RadialGradient` per building per tick,
/// all of it thrown away again; drawn on the canvas it is one shader and one
/// fill, and the geometry is the same one `RadialGradient.createShader`
/// would have produced (centre at `Alignment(0, 0.62)`, radius
/// `0.55 × shortestSide`), so nothing about it looks different.
class BuildingLife extends StatefulWidget {
  /// Where the chimney mouth is, in fractions of this box. Null for a
  /// building with no chimney — then only the glow is drawn.
  final (double, double)? chimney;

  /// Whether the lamplight pool is drawn at all.
  final bool glow;

  /// Distinct per building so neighbours are out of step. Any stable number
  /// does — the map passes the placed building's id hash.
  final int phaseSeed;

  const BuildingLife({
    super.key,
    this.chimney,
    this.glow = true,
    required this.phaseSeed,
  });

  @override
  State<BuildingLife> createState() => _BuildingLifeState();
}

class _BuildingLifeState extends State<BuildingLife>
    with _AmbientClockUser<BuildingLife> {
  /// Six seconds for one puff's whole life. Slower than it sounds: with four
  /// puffs staggered across it, one leaves the chimney every second and a half.
  static const double _smokeLifeSeconds = 6;

  /// One breath in (or out), in seconds — the glow swells over 4.2 s and
  /// fades back over the next 4.2.
  static const double _glowHalfPeriod = 4.2;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: AnimatedBuilder(
        animation: AmbientClock.instance,
        builder: (context, _) {
          final seconds = AmbientClock.instance.seconds;
          return CustomPaint(
            painter: _LifePainter(
              smokeT: (seconds / _smokeLifeSeconds) % 1.0,
              glowT: (seconds / _glowHalfPeriod) % 2.0,
              chimney: widget.chimney,
              glow: widget.glow,
              seed: widget.phaseSeed,
            ),
            size: Size.infinite,
          );
        },
      ),
    ),
  );
}

/// Smoke leaving a chimney: a few puffs rising, spreading and fading out.
/// A [BuildingLife] with the glow switched off — the map draws both together.
class ChimneySmoke extends StatelessWidget {
  /// Where the chimney mouth is, in fractions of this box.
  final double anchorX;
  final double anchorY;
  final int phaseSeed;

  const ChimneySmoke({
    super.key,
    required this.anchorX,
    required this.anchorY,
    required this.phaseSeed,
  });

  @override
  Widget build(BuildContext context) => BuildingLife(
    chimney: (anchorX, anchorY),
    glow: false,
    phaseSeed: phaseSeed,
  );
}

/// Lamplight breathing out of a building's lower half.
///
/// Deliberately NOT anchored to each window. It is a soft warm pool low on the
/// sprite, which is where doors and ground-floor windows are on every one of
/// these buildings — so it needs no per-picture measurement and works on art
/// that arrived from a prompt. A per-window glow would need a list of points
/// per building and would look wrong the moment one was off by a few pixels.
class LampGlow extends StatelessWidget {
  final int phaseSeed;

  const LampGlow({super.key, required this.phaseSeed});

  @override
  Widget build(BuildContext context) => BuildingLife(phaseSeed: phaseSeed);
}

class _LifePainter extends CustomPainter {
  final double smokeT;
  final double glowT;
  final (double, double)? chimney;
  final bool glow;
  final int seed;

  static const int _puffs = 4;

  // Reused across puffs and frames — only its shader changes.
  static final Paint _puffPaint = Paint();
  static final Paint _glowPaint = Paint();

  const _LifePainter({
    required this.smokeT,
    required this.glowT,
    required this.chimney,
    required this.glow,
    required this.seed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Light first, smoke over it — the order the two stacked widgets had.
    if (glow) _paintGlow(canvas, size);
    final anchor = chimney;
    if (anchor != null) _paintSmoke(canvas, size, anchor.$1, anchor.$2);
  }

  /// A slow breath with a small irregular tremor on top: a pure sine reads as
  /// a pulsing UI element, and a flame does not keep time.
  void _paintGlow(Canvas canvas, Size size) {
    // 0 → 1 → 0 triangle wave over two half-periods.
    final phase = glowT <= 1.0 ? glowT : 2.0 - glowT;
    final base = Curves.easeInOut.transform(phase);
    final tremor = math.sin((phase + seed % 13 / 13) * 17) * 0.12;
    final a = (0.10 + base * 0.09 + tremor * 0.03).clamp(0.0, 0.3);
    if (a <= 0.001) return;
    // Exactly what RadialGradient(center: Alignment(0, 0.62), radius: 0.55)
    // resolves to for this box: Alignment.withinRect for the centre, and
    // `radius × shortestSide` for the reach.
    final center = Offset(size.width / 2, size.height * (1 + 0.62) / 2);
    final reach = 0.55 * math.min(size.width, size.height);
    if (reach <= 0) return;
    _glowPaint.shader = ui.Gradient.radial(center, reach, [
      FoE.goldBright.withValues(alpha: a),
      FoE.goldBright.withValues(alpha: 0),
    ], const [0.0, 1.0]);
    canvas.drawRect(Offset.zero & size, _glowPaint);
  }

  void _paintSmoke(Canvas canvas, Size size, double anchorX, double anchorY) {
    final t = smokeT;
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
      final dx =
          drift * e * gust + math.sin(phase * 5 + i) * size.width * 0.012;
      final dy = -rise * e;
      final r = size.width * (0.022 + 0.055 * e);
      // Fades in over the first fifth so a puff is never born at full strength
      // in mid air, then out over the rest.
      final a = (phase < 0.2 ? phase / 0.2 : (1 - phase) / 0.8) * 0.34;
      if (a <= 0.01) continue;
      // A radial falloff instead of MaskFilter.blur: a blur is an extra
      // offscreen pass per puff per frame (four per chimney), a gradient is
      // one plain fill. Same soft-edged blob — solid core, fading out to
      // roughly where the blur's tail used to end.
      final center = Offset(ox + dx, oy + dy);
      final reach = r * 2.0;
      _puffPaint.shader = ui.Gradient.radial(
        center,
        reach,
        [
          FoE.parchment.withValues(alpha: a * 0.85),
          FoE.parchment.withValues(alpha: a * 0.5),
          FoE.parchment.withValues(alpha: 0),
        ],
        const [0.0, 0.4, 1.0],
      );
      canvas.drawCircle(center, reach, _puffPaint);
    }
  }

  @override
  bool shouldRepaint(_LifePainter old) =>
      old.smokeT != smokeT ||
      old.glowT != glowT ||
      old.glow != glow ||
      old.chimney != chimney ||
      old.seed != seed;
}

// ── A paused building sleeps (user 2026-09-22) ─────────────
// "3 mit der Graustufe von 1": the picture loses its colour and a little light,
// and instead of smoke sleepy Zs drift up from the chimney (or the roof, where
// there is none). It replaces the dark rectangle over the whole field and the
// 12 px ⏸ that used to be the only sign — a paused building read as a shadow on
// the ground, not as a building that has been told to rest.

/// Colours drained to 15 %, at 92 % of their light: what a paused building's
/// picture is drawn through. The luminance weights are Rec. 709, the same as CSS's
/// `grayscale()`, so the mock-up and the game agree.
final ColorFilter kPausedFilter = ColorFilter.matrix(pausedColorMatrix());

List<double> pausedColorMatrix({double keep = 0.15, double light = 0.92}) {
  final d = 1 - keep;
  final r = 0.2126 * d, g = 0.7152 * d, b = 0.0722 * d;
  double row(double own, double lum) => (own + lum) * light;
  return [
    row(keep, r), g * light, b * light, 0, 0, //
    r * light, row(keep, g), b * light, 0, 0, //
    r * light, g * light, row(keep, b), 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

/// Zs rising from [anchorX]/[anchorY] (fractions of this box): a small z, then two
/// bigger ones, each drifting up and right, growing and fading. One slow cycle on
/// the shared [AmbientClock], out of step between buildings.
class SleepZ extends StatefulWidget {
  final double anchorX;
  final double anchorY;
  final int phaseSeed;

  const SleepZ({
    super.key,
    required this.anchorX,
    required this.anchorY,
    required this.phaseSeed,
  });

  @override
  State<SleepZ> createState() => _SleepZState();
}

class _SleepZState extends State<SleepZ> with _AmbientClockUser<SleepZ> {
  /// One Z's whole life; three of them share it, a third apart.
  static const double _lifeSeconds = 5;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: AnimatedBuilder(
        animation: AmbientClock.instance,
        builder: (context, _) => CustomPaint(
          painter: _SleepZPainter(
            t: (AmbientClock.instance.seconds / _lifeSeconds) % 1.0,
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

class _SleepZPainter extends CustomPainter {
  final double t;
  final double anchorX;
  final double anchorY;
  final int seed;

  const _SleepZPainter({
    required this.t,
    required this.anchorX,
    required this.anchorY,
    required this.seed,
  });

  static const double _base = 22;
  static const List<String> _letters = ['z', 'Z', 'Z'];

  // Laid out once: the letter twice, filled and outlined, so the Zs read on any
  // roof and any grass.
  static final List<(TextPainter, TextPainter)> _glyphs = [
    for (final l in _letters)
      (_glyph(l, outline: false), _glyph(l, outline: true)),
  ];

  static TextPainter _glyph(String letter, {required bool outline}) {
    final style = outline
        ? TextStyle(
            fontSize: _base,
            fontWeight: FontWeight.w900,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4
              ..strokeJoin = StrokeJoin.round
              ..color = const Color(0xCC2A1A0C),
          )
        : const TextStyle(
            fontSize: _base,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          );
    return TextPainter(
      text: TextSpan(text: letter, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Sized off the building's WIDTH, like the smoke: the same on a hut and a hall.
    final unit = (size.width / 200).clamp(0.6, 1.5);
    final ox = size.width * anchorX;
    final oy = size.height * anchorY;
    for (var i = 0; i < _letters.length; i++) {
      final phase = (t + i / 3 + (seed % 89) / 89) % 1.0;
      // In over the first sixth, out over the last third.
      final a = phase < 0.16
          ? phase / 0.16
          : phase > 0.66
          ? (1 - phase) / 0.34
          : 1.0;
      if (a <= 0.02) continue;
      final rise = size.width * 0.30 * phase;
      final dx = size.width * 0.10 * phase + math.sin(phase * 6 + i) * unit * 3;
      final scale = unit * (0.55 + 0.7 * phase);
      final (fill, line) = _glyphs[i];
      canvas.saveLayer(
        null,
        Paint()..color = Color.fromRGBO(255, 255, 255, a * 0.95),
      );
      canvas.translate(ox + dx, oy - rise);
      canvas.scale(scale);
      final off = Offset(-fill.width / 2, -fill.height / 2);
      line.paint(canvas, off);
      fill.paint(canvas, off);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_SleepZPainter old) => old.t != t;
}
