import 'package:boddygame/features/settlement/widgets/building_life.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The map's smoke and lamp glow share ONE slow clock instead of a 60 fps
// controller each. It must run only while an effect is on screen.
void main() {
  Widget effects() => const Directionality(
    textDirection: TextDirection.ltr,
    child: SizedBox(
      width: 100,
      height: 100,
      child: Stack(
        children: [
          LampGlow(phaseSeed: 3),
          ChimneySmoke(anchorX: 0.5, anchorY: 0.3, phaseSeed: 3),
        ],
      ),
    ),
  );

  testWidgets('runs while an effect is mounted, stops when it is gone', (
    tester,
  ) async {
    expect(AmbientClock.instance.isRunning, isFalse);
    await tester.pumpWidget(effects());
    expect(AmbientClock.instance.isRunning, isTrue);
    await tester.pump(AmbientClock.period * 3); // paints without throwing
    await tester.pumpWidget(const SizedBox());
    expect(AmbientClock.instance.isRunning, isFalse);
  });

  testWidgets('a covered route (TickerMode off) does not keep it running', (
    tester,
  ) async {
    await tester.pumpWidget(TickerMode(enabled: false, child: effects()));
    expect(AmbientClock.instance.isRunning, isFalse);
    await tester.pumpWidget(TickerMode(enabled: true, child: effects()));
    expect(AmbientClock.instance.isRunning, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(AmbientClock.instance.isRunning, isFalse);
  });

  testWidgets('two effects count as two users', (tester) async {
    await tester.pumpWidget(effects());
    // Removing one of the two leaves the clock running for the other.
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(width: 100, height: 100, child: LampGlow(phaseSeed: 3)),
      ),
    );
    expect(AmbientClock.instance.isRunning, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(AmbientClock.instance.isRunning, isFalse);
  });
}
