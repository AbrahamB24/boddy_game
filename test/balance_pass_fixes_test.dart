import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/ability_def.dart';
import 'package:boddygame/features/creatures/models/combatant.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/status_effects.dart';
import 'package:boddygame/features/creatures/services/combat_engine.dart';
import 'package:boddygame/features/creatures/services/survival_run.dart';
import 'package:boddygame/features/settlement/data/item_definitions.dart';
import 'package:boddygame/features/settlement/services/daily_tasks.dart';
import 'package:boddygame/features/settlement/services/trade_center.dart';

// Fixes from the 2026-11-02 balance/QA pass — each test names the bug it
// pins, so a regression reads as the original report.

Combatant _mon(
  String id, {
  bool player = true,
  int hp = 200,
  int speed = 10,
  List<AbilityDef> abilities = const [],
}) => Combatant(
  id: id,
  name: id,
  element: CreatureElement.fire,
  rarity: CreatureRarity.common,
  isPlayerSide: player,
  level: 10,
  stage: 2,
  stats: {
    CreatureStat.hp: hp,
    CreatureStat.attack: 60,
    CreatureStat.defense: 30,
    CreatureStat.speed: speed,
    CreatureStat.catchRate: 5,
  },
  abilities: abilities,
);

CombatEngine _armed(List<Combatant> p, List<Combatant> e, {int seed = 1}) {
  final engine = CombatEngine(players: p, enemies: e, rng: math.Random(seed));
  for (final c in [...p, ...e]) {
    c.ap = maxActionPointsForStage(c.stage);
  }
  return engine;
}

void main() {
  group('a power-0 status move deals no damage', () {
    const intimidate = AbilityDef(
      id: 'einschuechterung',
      name: 'Intimidate',
      element: CreatureElement.neutral,
      kind: AbilityKind.damage,
      target: AbilityTarget.enemy,
      inflictDebuff: SecondaryDebuffKind.attackDown,
      inflictDebuffChance: 1.0,
      inflictDebuffTurns: 2,
      inflictDebuffValue: 0.2,
      apCost: 1,
    );

    test('the target keeps every HP and still gets the debuff', () {
      var landed = 0;
      for (var seed = 0; seed < 20; seed++) {
        final a = _mon('a', speed: 99, abilities: const [intimidate]);
        final b = _mon('b', player: false, speed: 1);
        final engine = _armed([a], [b], seed: seed);
        expect(engine.useAbility(a, intimidate, b), isNull);
        expect(b.hp, b.maxHp, reason: 'seed $seed: "No real hit" hit');
        expect(engine.lastEvents.any((e) => e.amount > 0), isFalse);
        if (b.secondaryDebuffs.containsKey(SecondaryDebuffKind.attackDown)) {
          landed++;
        }
      }
      // Misses are still possible (accuracy roll), but most land.
      expect(landed, greaterThan(10));
    });
  });

  group('a self-buff survives until an opponent has acted', () {
    test('a 1-turn armour cast on my turn is still up for the enemy turn', () {
      final a = _mon('a', speed: 20);
      final b = _mon('b', player: false, speed: 10);
      final engine = _armed([a], [b]);
      a.applySelfBuff(SelfBuffKind.armor, turns: 1, value: 0.2);
      engine.endTurn(); // my upkeep runs — the buff must outlive it
      expect(a.selfBuffs.containsKey(SelfBuffKind.armor), isTrue);
      expect(a.selfBuffs[SelfBuffKind.armor]!.turnsRemaining, 1);
      // My NEXT upkeep is where it runs out.
      a.tickStatusEndOfRound();
      expect(a.selfBuffs.containsKey(SelfBuffKind.armor), isFalse);
    });

    test('a 1-turn self-penalty is still there when the enemy hits back', () {
      final a = _mon('a');
      a.applySelfPenalty(
        const SelfPenalty(stat: SelfPenaltyStat.defense, mult: 0.8, turns: 1),
      );
      a.tickStatusEndOfRound(); // the turn it was used on
      expect(a.selfPenaltyStat, SelfPenaltyStat.defense);
      a.tickStatusEndOfRound(); // the next one
      expect(a.selfPenaltyStat, isNull);
    });

    test('enemy debuffs still count down from the first upkeep', () {
      final a = _mon('a');
      a.applySecondaryDebuff(SecondaryDebuffKind.speedDown, turns: 1);
      a.tickStatusEndOfRound();
      expect(a.secondaryDebuffs, isEmpty);
    });
  });

  group('the AI never wastes a self-heal on a full-HP caster', () {
    test('a hurt ally does not make a healthy caster heal itself', () {
      const selfHeal = AbilityDef(
        id: 'regeneration',
        name: 'Regeneration',
        element: CreatureElement.neutral,
        kind: AbilityKind.heal,
        target: AbilityTarget.self,
        healPct: 0.3,
        apCost: 2,
      );
      final healer = _mon('h', speed: 99, abilities: const [selfHeal]);
      final hurt = _mon('x', speed: 1)..hp = 20;
      final foe = _mon('f', player: false, speed: 1);
      final engine = _armed([healer, hurt], [foe]);
      engine.performAutoAction();
      expect(engine.playerAbilityUses['regeneration'], isNull);
      expect(foe.hp, lessThan(foe.maxHp), reason: 'it should attack instead');
    });
  });

  group('daily tasks never deal what cannot be done', () {
    test('excluded kinds are never rolled, on any day', () {
      const exclude = {
        DailyTaskKind.hatchEggs,
        DailyTaskKind.healMonsters,
        DailyTaskKind.craftItems,
      };
      for (var d = 0; d < 120; d++) {
        final day = DateTime.utc(2026, 1, 1).add(Duration(days: d));
        final s = rollDailyTasks(day, exclude: exclude);
        expect(s.tasks, hasLength(3));
        expect(s.tasks.map((t) => t.kind).toSet(), hasLength(3));
        for (final t in s.tasks) {
          expect(exclude.contains(t.kind), isFalse);
        }
      }
    });

    test('without exclusions the roll is unchanged', () {
      final day = DateTime.utc(2026, 11, 2);
      expect(
        rollDailyTasks(day).tasks.map((t) => t.kind).toList(),
        rollDailyTasks(
          day,
          exclude: const {},
        ).tasks.map((t) => t.kind).toList(),
      );
    });
  });

  group('gold is earned, not farmed (2026-11-02)', () {
    test('a first survival run still pays the full triangle', () {
      expect(goldRewardForFloors(10), goldRewardForFloors(10, previousBest: 0));
      expect(goldRewardForFloors(10), kSurvivalGoldPerFloor * 55);
    });

    test('repeating floors already reached pays only the token rate', () {
      final repeat = goldRewardForFloors(20, previousBest: 20);
      expect(repeat, 20 * kSurvivalRepeatGoldPerFloor);
      expect(repeat, lessThan(goldRewardForFloors(20) / 50));
    });

    test('beating the record pays the new floors at full rate', () {
      final r = goldRewardForFloors(12, previousBest: 10);
      expect(
        r,
        kSurvivalGoldPerFloor * (11 + 12) + 10 * kSurvivalRepeatGoldPerFloor,
      );
    });

    test('a shorter run than the record never pays record money', () {
      expect(
        goldRewardForFloors(5, previousBest: 20),
        5 * kSurvivalRepeatGoldPerFloor,
      );
    });

    test('a craftable item cannot be sold for gold', () {
      const cleanse = ItemDef(
        id: 'c',
        name: 'C',
        emoji: '🧼',
        description: '',
        ingredients: {'fish': 1},
        craftSeconds: 800,
        buyPrice: 12,
        sellPrice: 4,
      );
      expect(itemSellValue(cleanse), 0);
      // Found (non-craftable) items still sell, below their buy price.
      const found = ItemDef(
        id: 'f',
        name: 'F',
        emoji: '💎',
        description: '',
        craftSeconds: 0,
        buyPrice: 20,
        sellPrice: 6,
      );
      expect(itemSellValue(found), 6);
    });

    test('no bundled recipe can be sold at all', () {
      for (final def in kItemDefs.values) {
        if (def.ingredients.isEmpty && def.supplyCost <= 0) continue;
        expect(itemSellValue(def), 0, reason: def.id);
      }
    });
  });
}
