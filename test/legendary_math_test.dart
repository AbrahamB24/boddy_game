import 'package:flutter_test/flutter_test.dart';
import 'package:boddygame/features/creatures/models/legendary_math.dart';

void main() {
  test('stats approach a maximum, never pass it', () {
    final lv10 = LegendaryMath.equivalentLevel(10);
    final lv50 = LegendaryMath.equivalentLevel(50);
    final lv500 = LegendaryMath.equivalentLevel(500);
    expect(LegendaryMath.equivalentLevel(1), 1);
    expect(lv10, lessThan(lv50));
    expect(lv50, lessThan(lv500));
    expect(lv500, lessThan(81.0001)); // 1 + the dial's 80
  });

  test('every level helps less than the one before', () {
    final gains = [
      for (var l = 1; l < 30; l++)
        LegendaryMath.equivalentLevel(l + 1) - LegendaryMath.equivalentLevel(l),
    ];
    for (var i = 1; i < gains.length; i++) {
      expect(gains[i], lessThan(gains[i - 1]));
    }
  });

  test('the cooldown shrinks with the level but never reaches zero', () {
    expect(
      LegendaryMath.cooldownAt(20).inSeconds,
      lessThan(LegendaryMath.cooldownAt(1).inSeconds),
    );
    expect(LegendaryMath.cooldownAt(1000).inSeconds, greaterThan(0));
  });

  test('a trainer with no power adds nothing; five good ones add a lot', () {
    expect(LegendaryMath.trainerEffect(0, 20), 0);
    expect(LegendaryMath.trainerEffect(1, 20), greaterThan(1));
  });

  test('the reward shares add up to the whole', () {
    final sum = LegendaryMath.shares.fold<double>(0, (a, b) => a + b);
    expect(sum, closeTo(1.0, 1e-9));
  });
}
