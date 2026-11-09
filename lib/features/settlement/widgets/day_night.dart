import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/tuning/game_tuning.dart';

/// How far into the night the clock is: 0 = full day, 1 = deep night.
///
/// A plain curve over the local hour, so dusk and dawn are long, soft ramps
/// and not a switch: dusk 18:00 → 21:30, night until 05:00, dawn 05:00 → 08:00.
double nightAmount(DateTime t) {
  final h = t.hour + t.minute / 60 + t.second / 3600;
  double smooth(double x) => x * x * (3 - 2 * x);
  if (h >= 8 && h < 18) return 0;
  if (h >= 18 && h < 21.5) return smooth((h - 18) / 3.5);
  if (h >= 21.5 || h < 5) return 1;
  return 1 - smooth((h - 5) / 3);
}

/// The map's day / night: a moonlit blue MULTIPLIED over everything inside it,
/// following the device's real clock (re-read every minute).
///
/// Multiply, not a ColorFiltered: a filter would have to render the whole map
/// into an offscreen layer, a blend-moded rectangle is one more draw call. The
/// dev dials `nightMode` (auto / day / night) and `nightStrength` steer it.
class DayNightOverlay extends StatefulWidget {
  const DayNightOverlay({super.key});

  @override
  State<DayNightOverlay> createState() => _DayNightOverlayState();
}

class _DayNightOverlayState extends State<DayNightOverlay> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    GameTuning.i.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    GameTuning.i.removeListener(_changed);
    super.dispose();
  }

  /// Full night: dark, cold blue. Window-light-warm things stay readable
  /// because the red channel is kept highest.
  static const _night = Color(0xFF4A5C9C);

  @override
  Widget build(BuildContext context) {
    final mode = GameTuning.i.count('nightMode');
    final strength = GameTuning.i.raw('nightStrength').clamp(0.0, 1.0);
    final n = switch (mode) {
      1 => 0.0,
      2 => 1.0,
      _ => nightAmount(DateTime.now()),
    };
    final k = n * strength;
    if (k <= 0.002) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _MultiplyPainter(Color.lerp(Colors.white, _night, k)!),
        ),
      ),
    );
  }
}

class _MultiplyPainter extends CustomPainter {
  _MultiplyPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..color = color
      ..blendMode = BlendMode.multiply,
  );

  @override
  bool shouldRepaint(_MultiplyPainter old) => old.color != color;
}
