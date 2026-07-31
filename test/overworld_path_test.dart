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

    test('the cap climbs to 6 within Era II and never past it', () {
      // Somewhere in Era II the cap must reach the maximum of 6.
      final era2Boss = bossBattleForEra(2);
      expect(partySizeForBattle(era2Boss), kMaxPartySize);
      // And it is bounded there no matter how far the line runs.
      expect(partySizeForBattle(10000), kMaxPartySize);
    });

    test('3 is the Era-I cap: it is only exceeded once Era II begins', () {
      final era1Boss = bossBattleForEra(1);
      expect(partySizeForBattle(era1Boss), 3);
      // The step to 4 lands on Era II's first battle, not before.
      expect(partySizeForBattle(era1Boss + 1), 4);
    });

    test('unlockedPartySize mirrors the furthest battle reached', () {
      expect(unlockedPartySize(1), 1);
      expect(unlockedPartySize(6), 2);
      expect(unlockedPartySize(15), 3);
    });
  });

  group('battle ↔ era mapping (one continuous line)', () {
    test('the first segment is Era I, boss included', () {
      expect(eraForBattle(1), 1);
      expect(eraForBattle(kBattlesPerEra), 1);
      expect(eraForBattle(kBattlesPerEra + 1), 2);
    });

    test('bosses sit at the end of each era segment', () {
      expect(isBossBattle(kBattlesBeforeBoss), isFalse);
      expect(isBossBattle(bossBattleForEra(1)), isTrue);
      expect(isBossBattle(bossBattleForEra(2)), isTrue);
      expect(bossBattleForEra(1), kBattlesPerEra);
    });

    test('local index runs 1..kBattlesPerEra within an era', () {
      expect(localBattleIndex(1), 1);
      expect(localBattleIndex(kBattlesPerEra), kBattlesPerEra);
      expect(localBattleIndex(kBattlesPerEra + 1), 1);
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
      for (var n = 1; n <= bossBattleForEra(2); n++) {
        if (isBossBattle(n)) continue;
        final lvl = enemyLevelForBattle(n);
        expect(lvl, greaterThanOrEqualTo(prev), reason: 'battle $n');
        prev = lvl;
      }
    });

    test('bosses fight above their line position', () {
      final boss = bossBattleForEra(1);
      // A boss is stronger than the plain curve at its own position.
      expect(enemyLevelForBattle(boss), 1 + (boss - 1) ~/ 2 + kBossLevelBonus);
    });
  });

  group('enemy count is gated below the party you may bring', () {
    test('a regular battle never fields as many foes as your party allowance',
        () {
      // The whole point: you are never confronted with as many monsters as you
      // can bring until you have unlocked a bigger party.
      for (var n = 1; n <= bossBattleForEra(2); n++) {
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
