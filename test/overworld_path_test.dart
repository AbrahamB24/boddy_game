import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/services/overworld_path.dart';

void main() {
  group('party size on the linear path', () {
    test('the first five battles are always 1v1', () {
      for (var n = 1; n <= 5; n++) {
        expect(partySizeForBattle(n), 1, reason: 'battle $n');
      }
    });

    test("the user's Era-I anchors: +1 at battle 6, +1 at battle 15", () {
      expect(partySizeForBattle(5), 1);
      expect(partySizeForBattle(6), 2);
      expect(partySizeForBattle(14), 2);
      expect(partySizeForBattle(15), 3);
    });

    test('the cap climbs to 6 within region II and never past it', () {
      // Somewhere in region II the cap must reach the maximum of 6.
      final region2Boss = 2 * kFallbackBattlesPerRegion;
      expect(partySizeForBattle(region2Boss), kMaxPartySize);
      // And it is bounded there no matter how far the line runs.
      expect(partySizeForBattle(10000), kMaxPartySize);
    });

    test('3 is the region-I cap: it is only exceeded once region II begins',
        () {
      final region1Boss = kFallbackBattlesPerRegion;
      expect(partySizeForBattle(region1Boss), 3);
      // The step to 4 lands on region II's first battle, not before.
      expect(partySizeForBattle(region1Boss + 1), 4);
    });

    test('unlockedPartySize mirrors the furthest battle reached', () {
      expect(unlockedPartySize(1), 1);
      expect(unlockedPartySize(6), 2);
      expect(unlockedPartySize(15), 3);
    });
  });

  group('isBossBattle fallback formula (real content overrides via '
      "PathNode.isBoss — see path_node.dart's regionForBattle)", () {
    test('bosses sit at the end of each fallback region segment', () {
      expect(isBossBattle(kBattlesBeforeBoss), isFalse);
      expect(isBossBattle(kFallbackBattlesPerRegion), isTrue);
      expect(isBossBattle(2 * kFallbackBattlesPerRegion), isTrue);
    });
  });

  group('enemy scaling', () {
    test('starts low so a level-1 starter can win the opening fights', () {
      expect(enemyLevelForBattle(1), lessThanOrEqualTo(2));
    });

    test('the regular-battle curve rises monotonically up the line', () {
      // Bosses spike above the curve, so the fight AFTER a boss dips back to it
      // — that break is by design. The regular fights themselves never drop.
      var prev = 0;
      for (var n = 1; n <= 2 * kFallbackBattlesPerRegion; n++) {
        if (isBossBattle(n)) continue;
        final lvl = enemyLevelForBattle(n);
        expect(lvl, greaterThanOrEqualTo(prev), reason: 'battle $n');
        prev = lvl;
      }
    });

    test('bosses fight above their line position', () {
      final boss = kFallbackBattlesPerRegion;
      // A boss is stronger than the plain curve at its own position.
      expect(enemyLevelForBattle(boss), 1 + (boss - 1) ~/ 2 + kBossLevelBonus);
    });
  });

  group('enemy count is gated below the party you may bring', () {
    test('a regular battle never fields as many foes as your party allowance',
        () {
      // The whole point: you are never confronted with as many monsters as you
      // can bring until you have unlocked a bigger party.
      for (var n = 1; n <= 2 * kFallbackBattlesPerRegion; n++) {
        expect(enemyCountForBattle(n), lessThan(partySizeForBattle(n) + 1));
        expect(enemyCountForBattle(n), lessThanOrEqualTo(partySizeForBattle(n)));
        expect(enemyCountForBattle(n), greaterThanOrEqualTo(1));
      }
    });

    test('you always outnumber once you can bring more than one', () {
      // party 2 (battle 6) → still one foe; a second foe waits until party 3.
      expect(enemyCountForBattle(6), 1);
      expect(partySizeForBattle(6), 2);
      expect(enemyCountForBattle(15), 2);
      expect(partySizeForBattle(15), 3);
    });

    test('the first five battles are 1v1', () {
      for (var n = 1; n <= 5; n++) {
        expect(enemyCountForBattle(n), 1, reason: 'battle $n');
      }
    });
  });
}
