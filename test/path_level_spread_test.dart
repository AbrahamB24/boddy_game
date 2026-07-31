import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/path_node.dart';

// ── Gesamtlevel statt Einzellevel (user 2026-07-30) ─────────
// "jetzt will ich nicht die level der Monster einzeln eingeben, sondern den
// Gesamtlevel und diese werden einigermassen gleichmässig auf alle Monster
// verteilt, auch wenn es Unterschiede geben darf (max 20% Abweichung)."
//
// Two promises that pull against each other — an EXACT sum and a spread — which
// is exactly why this is worth pinning: the obvious implementation (jitter each
// share and round) satisfies the second and quietly breaks the first, and a node
// labelled 60 then fields 58.
void main() {
  test('the sum is exactly what was asked for', () {
    for (var seed = 0; seed < 50; seed++) {
      for (final (total, count) in [(60, 3), (100, 4), (37, 2), (9, 3), (250, 5)]) {
        final levels = spreadLevels(
          total: total,
          count: count,
          rng: math.Random(seed),
        );
        expect(levels.length, count);
        expect(levels.reduce((a, b) => a + b), total,
            reason: 'seed $seed · $total over $count');
      }
    }
  });

  test('nobody strays more than 20 % from the even share', () {
    for (var seed = 0; seed < 50; seed++) {
      const total = 90;
      const count = 3;
      final levels =
          spreadLevels(total: total, count: count, rng: math.Random(seed));
      final share = total / count;
      for (final l in levels) {
        expect(l, greaterThanOrEqualTo((share * 0.8).floor()),
            reason: 'seed $seed: $levels');
        expect(l, lessThanOrEqualTo((share * 1.2).ceil()),
            reason: 'seed $seed: $levels');
      }
    }
  });

  test('there IS a spread — not three identical clones', () {
    // Over many rolls the levels must actually differ sometimes, or "max 20 %
    // Abweichung" is a band nothing ever uses.
    var sawDifference = false;
    for (var seed = 0; seed < 30; seed++) {
      final levels = spreadLevels(total: 100, count: 4, rng: math.Random(seed));
      if (levels.toSet().length > 1) sawDifference = true;
    }
    expect(sawDifference, isTrue);
  });

  test('no monster is ever below level 1', () {
    for (var seed = 0; seed < 20; seed++) {
      for (final (total, count) in [(1, 3), (2, 5), (0, 2), (-5, 2)]) {
        final levels =
            spreadLevels(total: total, count: count, rng: math.Random(seed));
        expect(levels.every((l) => l >= 1), isTrue,
            reason: '$total over $count → $levels');
        expect(levels.length, count);
      }
    }
  });

  test('a single monster simply gets the whole total', () {
    for (var seed = 0; seed < 10; seed++) {
      expect(spreadLevels(total: 42, count: 1, rng: math.Random(seed)), [42]);
    }
  });

  test('no monsters, no levels', () {
    expect(spreadLevels(total: 50, count: 0, rng: math.Random(1)), isEmpty);
  });

  test('a tighter band is honoured too', () {
    // The jitter is a parameter, not a constant baked into the maths.
    for (var seed = 0; seed < 20; seed++) {
      final levels = spreadLevels(
        total: 100,
        count: 4,
        rng: math.Random(seed),
        jitter: 0,
      );
      expect(levels, everyElement(25), reason: 'no jitter, no spread');
      expect(levels.reduce((a, b) => a + b), 100);
    }
  });
}
