import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/combatant.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/services/battle_stars.dart';
import 'package:boddygame/features/creatures/services/star_overview.dart';
import 'package:boddygame/features/settlement/settlement_controller.dart';

// Stars for a won campaign battle (user 2026-09-28). The criteria must not
// depend on how many monsters fought: they are ticks and fractions only.
Combatant mon(String id, {required int hp, int max = 100}) {
  final c = Combatant(
    id: id,
    name: id,
    element: CreatureElement.fire,
    rarity: CreatureRarity.common,
    isPlayerSide: true,
    level: 10,
    stage: 0,
    stats: {
      CreatureStat.hp: max,
      CreatureStat.attack: 50,
      CreatureStat.defense: 30,
      CreatureStat.speed: 10,
      CreatureStat.catchRate: 5,
    },
    abilities: const [],
  );
  c.hp = hp;
  return c;
}

void main() {
  group('judgeBattle', () {
    test('a flawless win is three stars', () {
      final s = judgeBattle(won: true, players: [mon('a', hp: 90)]);
      expect(s.count, 3);
      expect(s.noKnockOut, isTrue);
      expect(s.hpKept, isTrue);
    });

    test('a win with a monster knocked out loses the second star', () {
      final s = judgeBattle(
        won: true,
        players: [mon('a', hp: 100), mon('b', hp: 0)],
      );
      expect(s.noKnockOut, isFalse);
      // 100 of 200 = 50 %: below the HP line too.
      expect(s.count, 1);
    });

    test('team size does not matter: the same yardstick for 1 and 6', () {
      final one = judgeBattle(won: true, players: [mon('a', hp: 70)]);
      final six = judgeBattle(
        won: true,
        players: [for (var i = 0; i < 6; i++) mon('m$i', hp: 70)],
      );
      expect(one.count, six.count);
      expect(six.hpLeft, closeTo(0.7, 1e-9));
    });

    test('the third star is a share of MAX HP, not of what it started with', () {
      final below = judgeBattle(won: true, players: [mon('a', hp: 59)]);
      final on = judgeBattle(won: true, players: [mon('a', hp: 60)]);
      expect(below.hpKept, isFalse);
      expect(on.hpKept, isTrue);
      expect(below.count, 2); // won + nobody knocked out
      expect(on.count, 3);
    });

    test('a lost fight earns nothing', () {
      expect(judgeBattle(won: false, players: [mon('a', hp: 0)]).count, 0);
    });
  });

  group('what the stars pay', () {
    test('more stars, more XP', () {
      double x(int hp, {int ko = 0}) => judgeBattle(
        won: true,
        players: [mon('a', hp: hp), for (var i = 0; i < ko; i++) mon('k$i', hp: 0)],
      ).xpMultiplier;
      expect(x(90), 1.5);
      expect(x(40), 1.25);
      expect(x(90, ko: 1), 1.0); // 90 of 200 HP and one knocked out: one star
    });

    test('gold comes ONCE per new star, and only from the second', () {
      expect(firstTimeStarGold(0, 1), 0);
      expect(firstTimeStarGold(0, 3), kStarFirstTimeGold[2]! + kStarFirstTimeGold[3]!);
      expect(firstTimeStarGold(2, 3), kStarFirstTimeGold[3]);
      expect(firstTimeStarGold(3, 3), 0);
      expect(firstTimeStarGold(2, 1), 0);
    });
  });

  group('the record', () {
    late SettlementController ctrl;
    setUp(() {
      ctrl = SettlementController();
      ctrl.battleStars = {};
    });
    tearDown(() => ctrl.battleStars = {});

    Future<void> run(Future<void> Function() f) async {
      // Saving needs a Supabase client the tests do not have; the local state is
      // settled before that await, which is all these tests read.
      try {
        await f();
      } catch (_) {}
    }

    test('a better result raises the record, a worse one never lowers it', () async {
      await run(() => ctrl.recordBattleStars(7, 2));
      expect(ctrl.starsFor(7), 2);
      await run(() => ctrl.recordBattleStars(7, 1));
      expect(ctrl.starsFor(7), 2);
      await run(() => ctrl.recordBattleStars(7, 3));
      expect(ctrl.starsFor(7), 3);
      expect(ctrl.totalStars, 3);
    });
  });

  group('the overview', () {
    test('totals add up and never exceed 3 per battle', () {
      final o = starOverview(stars: {1: 3, 2: 1}, battlesCleared: 2);
      final t = starTotals(stars: {1: 3, 2: 1}, battlesCleared: 2);
      expect(t.earned, 4);
      expect(t.max, o.fold<int>(0, (a, r) => a + r.max));
      for (final r in o) {
        expect(r.max, r.battles.length * 3);
        expect(r.earned, lessThanOrEqualTo(r.max));
      }
    });
  });
}
