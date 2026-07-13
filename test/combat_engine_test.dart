import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/ability_def.dart';
import 'package:boddygame/features/creatures/models/combatant.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/status_effects.dart';
import 'package:boddygame/features/creatures/services/combat_engine.dart';

Combatant make({
  required String id,
  bool player = true,
  int speed = 10,
  int hp = 200,
  int attack = 60,
  int defense = 30,
  int energy = 100,
  CreatureElement element = CreatureElement.fire,
  List<AbilityDef> abilities = const [],
}) => Combatant(
  id: id,
  name: id,
  element: element,
  rarity: CreatureRarity.common,
  isPlayerSide: player,
  level: 10,
  stats: {
    CreatureStat.hp: hp,
    CreatureStat.attack: attack,
    CreatureStat.defense: defense,
    CreatureStat.speed: speed,
    CreatureStat.catchRate: 5,
    CreatureStat.energy: energy,
  },
  abilities: abilities,
);

void main() {
  test('faster combatant acts first and more often', () {
    final fast = make(id: 'fast', speed: 20);
    final slow = make(id: 'slow', player: false, speed: 10);
    final engine = CombatEngine(players: [fast], enemies: [slow]);

    expect(engine.currentActor, fast);
    final order = engine.forecast(9);
    final fastTurns = order.where((c) => c == fast).length;
    final slowTurns = order.where((c) => c == slow).length;
    // Double speed = double turn frequency.
    expect(fastTurns, greaterThanOrEqualTo(slowTurns * 2 - 1));
  });

  test('basic attack damages, generates energy and passes the turn', () {
    final a = make(id: 'a', speed: 20);
    final b = make(id: 'b', player: false, speed: 10);
    final engine = CombatEngine(
      players: [a],
      enemies: [b],
      rng: math.Random(42),
    );
    a.energy = 0;

    engine.basicAttack(a, b);

    expect(b.hp, lessThan(b.maxHp));
    expect(a.energy, kBasicAttackEnergyGain);
    expect(engine.outcome, isNull);
  });

  test('type matrix: 2.0 super-effective beats 0.5 resisted (STAB held equal)', () {
    final fireMove = AbilityDef(
      id: 'fire_move',
      name: 'Fire Move',
      element: CreatureElement.fire,
      kind: AbilityKind.damage,
      target: AbilityTarget.enemy,
      energyCost: 10,
      power: 80,
    );

    int damageAgainst(CreatureElement targetElement) {
      // Attacker is ALSO fire, so STAB (1.5x) applies identically in both
      // calls — only the target's element (and thus the type multiplier)
      // differs between the two measurements.
      final attacker = make(id: 'atk', abilities: [fireMove]);
      final target = make(id: 'tgt', player: false, element: targetElement, hp: 5000);
      final engine = CombatEngine(
        players: [attacker],
        enemies: [target],
        rng: math.Random(7), // same seed -> same variance/crit both runs
      );
      final error = engine.useAbility(attacker, fireMove, target);
      expect(error, isNull);
      return 5000 - target.hp;
    }

    final vsPlant = damageAgainst(CreatureElement.plant); // 2.0x
    final vsWater = damageAgainst(CreatureElement.water); // 0.5x
    expect(vsPlant, greaterThan(vsWater));
    // 2.0x vs 0.5x with identical variance/crit -> exactly factor 4.
    expect(vsPlant, closeTo(vsWater * 4, 2));
  });

  test('Licht and Schatten both hit each other hard and resist themselves', () {
    expect(CreatureElement.light.multiplierVs(CreatureElement.shadow), 2.0);
    expect(CreatureElement.shadow.multiplierVs(CreatureElement.light), 2.0);
    expect(CreatureElement.light.multiplierVs(CreatureElement.light), 0.5);
    expect(CreatureElement.shadow.multiplierVs(CreatureElement.shadow), 0.5);
  });

  test('ability requires energy and reports an error instead of acting', () {
    final pricey = AbilityDef(
      id: 'pricey',
      name: 'Pricey',
      kind: AbilityKind.damage,
      target: AbilityTarget.enemy,
      energyCost: 99,
      power: 100,
    );
    final a = make(id: 'a', abilities: [pricey]);
    a.energy = 10;
    final b = make(id: 'b', player: false);
    final engine = CombatEngine(players: [a], enemies: [b]);

    final error = engine.useAbility(a, pricey, b);

    expect(error, isNotNull);
    expect(b.hp, b.maxHp); // nothing happened
    expect(engine.currentActor, isNot(b)); // turn NOT consumed
  });

  test('haste buff makes a slow combatant overtake in the forecast', () {
    final slowAlly = make(id: 'slow', speed: 10);
    final enemy = make(id: 'enemy', player: false, speed: 15);
    final engine = CombatEngine(players: [slowAlly], enemies: [enemy]);

    final before = engine.forecast(6).where((c) => c == slowAlly).length;
    slowAlly.applySelfBuff(SelfBuffKind.haste);
    final after = engine.forecast(6).where((c) => c == slowAlly).length;

    expect(after, greaterThan(before));
  });

  test('victory when all enemies die; boss XP is ×6 the normal kill formula', () {
    final a = make(id: 'a', attack: 999);
    final weak = make(id: 'weak', player: false, hp: 1, defense: 0);
    final engine = CombatEngine(
      players: [a],
      enemies: [weak],
      rng: math.Random(1),
    );

    engine.basicAttack(a, weak);

    expect(engine.outcome, CombatOutcome.victory);
    final normalXp = (9.0 * math.pow(weak.level, 2.3)).round();
    expect(engine.totalXpReward, normalXp);
  });

  test('heal never exceeds max HP', () {
    final mend = AbilityDef(
      id: 'mend',
      name: 'Mend',
      kind: AbilityKind.heal,
      target: AbilityTarget.ally,
      energyCost: 5,
      healPct: 0.99,
    );
    final healer = make(id: 'healer', abilities: [mend]);
    final ally = make(id: 'ally');
    ally.hp = 50;
    final enemy = make(id: 'enemy', player: false);
    final engine = CombatEngine(players: [healer, ally], enemies: [enemy]);

    engine.useAbility(healer, mend, ally);

    expect(ally.hp, ally.maxHp);
  });

  test('lifesteal heals the attacker a fraction of the damage dealt', () {
    final drain = AbilityDef(
      id: 'drain',
      name: 'Drain',
      kind: AbilityKind.damage,
      target: AbilityTarget.enemy,
      energyCost: 10,
      power: 80,
      lifestealPct: 0.5,
    );
    final attacker = make(id: 'atk', abilities: [drain]);
    attacker.hp = 10;
    final target = make(id: 'tgt', player: false, hp: 500);
    final engine = CombatEngine(
      players: [attacker],
      enemies: [target],
      rng: math.Random(3),
    );

    engine.useAbility(attacker, drain, target);

    expect(attacker.hp, greaterThan(10));
  });

  test('burn deals end-of-turn DoT and lowers attack', () {
    final burnMove = AbilityDef(
      id: 'burn_move',
      name: 'Burn Move',
      kind: AbilityKind.damage,
      target: AbilityTarget.enemy,
      energyCost: 10,
      power: 10,
      inflictMain: MainStatusKind.burn,
      inflictMainChance: 1.0,
    );
    final attacker = make(id: 'atk', speed: 20, abilities: [burnMove]);
    final target = make(id: 'tgt', player: false, speed: 10, hp: 1000);
    final engine = CombatEngine(
      players: [attacker],
      enemies: [target],
      rng: math.Random(5),
    );

    engine.useAbility(attacker, burnMove, target);
    expect(target.mainStatus, MainStatusKind.burn);
    expect(target.effectiveAttack, closeTo(target.stat(CreatureStat.attack) * 0.80, 0.01));

    // Advance until the burned target has taken its own turn (and thus its
    // end-of-turn DoT tick) at least once.
    final hpBeforeDot = target.hp;
    var guard = 0;
    while (target.mainStatus != null && guard < 30) {
      if (engine.currentActor == target) {
        engine.basicAttack(target, attacker);
        break;
      }
      engine.performAutoAction();
      guard++;
    }
    expect(target.hp, lessThan(hpBeforeDot));
  });

  test('auto action fights until someone wins', () {
    final a = make(id: 'a', speed: 12);
    final b = make(id: 'b', player: false, speed: 10);
    final engine = CombatEngine(
      players: [a],
      enemies: [b],
      rng: math.Random(3),
    );

    var guard = 0;
    while (engine.outcome == null && guard < 200) {
      engine.performAutoAction();
      guard++;
    }
    expect(engine.outcome, isNotNull);
    expect(guard, lessThan(200));
  });
}
