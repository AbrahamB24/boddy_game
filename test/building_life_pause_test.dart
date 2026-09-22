import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/widgets/building_life.dart';

// A paused building (user 2026-09-22, "Schlaf-Z mit der Graustufe"): its picture
// is drawn through a grey filter, and sleepy Zs replace the smoke.
void main() {
  /// The matrix applied to an RGB colour (0–255), the way ColorFilter does.
  List<double> apply(List<double> m, double r, double g, double b) => [
    m[0] * r + m[1] * g + m[2] * b,
    m[5] * r + m[6] * g + m[7] * b,
    m[10] * r + m[11] * g + m[12] * b,
  ];

  test('colours are drained to 15 % and dimmed to 92 %', () {
    final m = pausedColorMatrix();
    // White keeps its balance and loses 8 % of its light.
    final white = apply(m, 255, 255, 255);
    for (final c in white) {
      expect(c, closeTo(255 * 0.92, 0.5));
    }
    // Pure red is mostly grey now: the channels are close, red slightly ahead.
    final red = apply(m, 255, 0, 0);
    expect(red[0], greaterThan(red[1]));
    expect(red[0] - red[1], lessThan(40));
    // A grey stays a grey.
    final grey = apply(m, 120, 120, 120);
    expect(grey[0], closeTo(grey[1], 0.5));
    expect(grey[1], closeTo(grey[2], 0.5));
  });

  testWidgets('the Zs animate on the shared clock without error', (t) async {
    await t.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 250,
            child: SleepZ(anchorX: 0.6, anchorY: 0.2, phaseSeed: 7),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 400));
    }
    expect(t.takeException(), isNull);
    expect(AmbientClock.instance.isRunning, isTrue);
    // Unmounting stops the clock again.
    await t.pumpWidget(const SizedBox());
    expect(AmbientClock.instance.isRunning, isFalse);
  });
}
