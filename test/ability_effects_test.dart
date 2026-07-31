import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/core/tuning/game_tuning.dart';

import 'package:boddygame/features/creatures/models/ability_def.dart';
import 'package:boddygame/features/creatures/models/combatant.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/status_effects.dart';
import 'package:boddygame/features/creatures/services/combat_engine.dart';

// ── An ability's effects (user 2026-07-30) ──────────────────
// "Wenn ich einen Effect auswähle für eine Fähigkeit, zeige mir ganz genau, was
// dies im Kampf bedeutet … Effekt wählen (alle effekte in einer Liste), Dauer (0
// default, falls es nicht auf Zeit ist), Wert des Effekts (bsp wieviel HP burn
// verursacht)."
//
// Three rules carry that, and each one fails SILENTLY if it breaks:
//   • 0 means the catalog default — otherwise every ability authored before this
//     existed would quietly go to zero damage / zero turns.
//   • the authored number is what the FIGHT uses, not just what the form prints.
//   • the words in the form come from the same numbers the engine applies.

Combatant _mob({int hp = 200, int speed = 100, String id = 'm'}) => Combatant(
  id: id,
  name: id,
  element: CreatureElement.fire,
  rarity: CreatureRarity.common,
  isPlayerSide: true,
  level: 10,
  stats: {
    CreatureStat.hp: hp,
    CreatureStat.attack: 50,
    CreatureStat.defense: 50,
    CreatureStat.speed: speed,
  },
  abilities: const [],
);

AbilityDef _burn({int turns = 0, double value = 0, double chance = 1}) =>
    AbilityDef(
      id: 'b',
      name: 'Burn',
      element: CreatureElement.fire,
      kind: AbilityKind.damage,
      target: AbilityTarget.enemy,
      power: 40,
      inflictMain: MainStatusKind.burn,
      inflictMainChance: chance,
      inflictMainTurns: turns,
      inflictMainValue: value,
    );

void main() {
  group('0 means the catalog default', () {
    test('an untouched status burns exactly as it always did', () {
      final t = _mob();
      t.applyMainStatus(MainStatusKind.burn);
      expect(t.mainStatusTurnsRemaining, mainStatusDuration(MainStatusKind.burn));
      expect(
        t.mainStatusValue,
        closeTo(statusDotFraction(MainStatusKind.burn, 0), 1e-9),
      );
      // …and the DoT that follows is the catalog's 5 % of max HP.
      final dot = t.tickStatusEndOfRound();
      expect(dot, (200 * statusDotFraction(MainStatusKind.burn, 0)).round());
    });

    test('an untouched debuff and buff too', () {
      final t = _mob();
      t.applySecondaryDebuff(SecondaryDebuffKind.blind);
      expect(
        t.effectiveAccuracy,
        closeTo(secondaryAccuracyMult(SecondaryDebuffKind.blind), 1e-9),
      );
      t.applySelfBuff(SelfBuffKind.armor);
      expect(
        t.effectiveDefense,
        closeTo(50 * selfBuffDefenseMult(SelfBuffKind.armor), 1e-9),
      );
    });

    test('the effect list reports the resolved numbers, not the raw 0s', () {
      final e = _burn().effects.single;
      expect(e.turns, 0, reason: 'nothing was authored');
      expect(e.resolvedTurns, mainStatusDuration(MainStatusKind.burn));
      expect(e.resolvedValue, statusDotFraction(MainStatusKind.burn, 0));
    });
  });

  group('an authored number reaches the fight', () {
    test('burn: the value IS the damage per turn', () {
      final t = _mob(hp: 300);
      t.applyMainStatus(MainStatusKind.burn, turns: 5, value: 0.10);
      expect(t.mainStatusTurnsRemaining, 5);
      expect(t.tickStatusEndOfRound(), 30); // 10 % of 300
      // Five turns, then it is gone.
      for (var i = 0; i < 4; i++) {
        t.tickStatusEndOfRound();
      }
      expect(t.mainStatus, isNull);
    });

    test('frost: the value is the SPEED lost, and the skip chance stays fixed',
        () {
      final t = _mob(speed: 100);
      t.applyMainStatus(MainStatusKind.frost, value: 0.75);
      expect(t.effectiveSpeed, closeTo(25, 1e-9));
      // Frost's own 10 % turn loss is not the authored number — it is what being
      // frozen is, and the form says so.
      var skips = 0;
      final rng = math.Random(7);
      for (var i = 0; i < 400; i++) {
        if (t.rollSkipTurn(rng)) skips++;
      }
      expect(skips / 400, closeTo(statusSkipChance(MainStatusKind.frost), 0.06));
    });

    test('fear: the value IS the chance to lose the turn', () {
      final t = _mob();
      t.applyMainStatus(MainStatusKind.fear, value: 0.90);
      var skips = 0;
      final rng = math.Random(3);
      for (var i = 0; i < 400; i++) {
        if (t.rollSkipTurn(rng)) skips++;
      }
      expect(skips / 400, closeTo(0.90, 0.06));
    });

    test('blind and slow move accuracy and speed by their own value', () {
      final t = _mob(speed: 200);
      t.applySecondaryDebuff(SecondaryDebuffKind.blind, value: 0.5);
      t.applySecondaryDebuff(SecondaryDebuffKind.speedDown, value: 0.25);
      expect(t.effectiveAccuracy, closeTo(0.5, 1e-9));
      expect(t.effectiveSpeed, closeTo(150, 1e-9));
    });

    test('a buff gains what it says, for as long as it says', () {
      final t = _mob(speed: 100);
      t.applySelfBuff(SelfBuffKind.haste, turns: 4, value: 1.0);
      expect(t.effectiveSpeed, closeTo(200, 1e-9));
      for (var i = 0; i < 3; i++) {
        t.tickStatusEndOfRound();
      }
      expect(t.effectiveSpeed, closeTo(200, 1e-9), reason: 'still on turn 4');
      t.tickStatusEndOfRound();
      expect(t.effectiveSpeed, closeTo(100, 1e-9));
    });

    test('the engine hands the ABILITY\'s numbers over, not the catalog\'s', () {
      // The whole point: two fire moves that differ in more than power.
      final attacker = _mob(id: 'a');
      final target = _mob(id: 'd', hp: 400);
      final engine = CombatEngine(
        players: [attacker],
        enemies: [target],
        rng: math.Random(1),
      );
      attacker.ap = 8;
      engine.useAbility(attacker, _burn(turns: 9, value: 0.25), target);
      expect(target.mainStatus, MainStatusKind.burn);
      expect(target.mainStatusTurnsRemaining, 9);
      expect(target.mainStatusValue, closeTo(0.25, 1e-9));
    });
  });

  group('the list is a view over the slots', () {
    test('every family round-trips through effects → withEffects', () {
      final base = AbilityDef(
        id: 'x',
        name: 'X',
        element: CreatureElement.water,
        kind: AbilityKind.damage,
        target: AbilityTarget.enemy,
        power: 50,
      );
      final authored = [
        const AbilityEffect(
          kind: AbilityEffectKind.poison,
          chance: 0.5,
          turns: 6,
          value: 0.08,
        ),
        const AbilityEffect(kind: AbilityEffectKind.slow, chance: 0.3),
        const AbilityEffect(kind: AbilityEffectKind.lifesteal, value: 0.4),
        const AbilityEffect(kind: AbilityEffectKind.selfDefDown, value: 0.2),
      ];
      final def = base.withEffects(authored);
      // Stored in the slots the engine already reads…
      expect(def.inflictMain, MainStatusKind.poison);
      expect(def.inflictMainTurns, 6);
      expect(def.inflictMainValue, 0.08);
      expect(def.inflictDebuff, SecondaryDebuffKind.speedDown);
      expect(def.lifestealPct, 0.4);
      // …and a self-cost keeps being the MULTIPLIER it always was on the way in.
      expect(def.selfPenaltyStat, SelfPenaltyStat.defense);
      expect(def.selfPenaltyMult, closeTo(0.8, 1e-9));
      // …and reads back as the same list.
      final back = def.effects;
      expect(back.map((e) => e.kind), [
        AbilityEffectKind.poison,
        AbilityEffectKind.slow,
        AbilityEffectKind.lifesteal,
        AbilityEffectKind.selfDefDown,
      ]);
      expect(back.first.turns, 6);
      expect(back.last.resolvedValue, closeTo(0.2, 1e-9));
    });

    test('one per family — a second main status cannot be stored', () {
      // Not a validation message but a fact: the engine can only ever apply one
      // (main statuses are mutually exclusive on the target).
      final def = AbilityDef(
        id: 'x',
        name: 'X',
        element: CreatureElement.fire,
        kind: AbilityKind.damage,
        target: AbilityTarget.enemy,
      ).withEffects(const [
        AbilityEffect(kind: AbilityEffectKind.burn),
        AbilityEffect(kind: AbilityEffectKind.frost),
      ]);
      expect(def.inflictMain, MainStatusKind.frost, reason: 'last one wins');
      expect(def.effects.where((e) => e.kind.mainStatus != null).length, 1);
    });

    test('the row round-trips the new numbers', () {
      final def = _burn(turns: 7, value: 0.12);
      final back = AbilityDef.fromDefRow(def.toDefRow());
      expect(back.inflictMainTurns, 7);
      expect(back.inflictMainValue, closeTo(0.12, 1e-9));
    });

    test('a pre-migration row (no columns) still loads as the default', () {
      final back = AbilityDef.fromDefRow({
        'id': 'old',
        'name': 'Old',
        'kind': 'damage',
        'target': 'enemy',
        'power': 40,
        'inflict_main': 'burn',
        'inflict_main_chance': 0.3,
      });
      expect(back.inflictMainTurns, 0);
      expect(back.effects.single.resolvedTurns,
          mainStatusDuration(MainStatusKind.burn));
    });
  });

  group('the form says exactly what the fight does', () {
    test('burn states the damage, the duration AND the hidden attack sap', () {
      final lines = describeAbilityEffect(const AbilityEffect(
        kind: AbilityEffectKind.burn,
        turns: 4,
        value: 0.10,
      )).join(' ');
      expect(lines, contains('10 %'));
      expect(lines, contains('4 turns'));
      // The part nobody could see before: picking Burn also saps attack.
      expect(lines, contains('attacks for'));
      expect(
        lines,
        contains(
          '${((1 - statusAttackMult(MainStatusKind.burn)) * 100).round()} %',
        ),
      );
    });

    test('poison states the escalation and the total', () {
      final lines = describeAbilityEffect(const AbilityEffect(
        kind: AbilityEffectKind.poison,
        turns: 3,
        value: 0.06,
      )).join(' ');
      expect(lines, contains('MORE every turn'));
      expect(lines, contains('Total'));
    });

    test('an untimed effect says so instead of quoting a duration', () {
      for (final k in [AbilityEffectKind.heal, AbilityEffectKind.lifesteal]) {
        expect(k.isTimed, isFalse, reason: k.name);
        expect(AbilityEffect(kind: k).resolvedTurns, 0, reason: k.name);
        expect(describeAbilityEffect(AbilityEffect(kind: k)).join(' '),
            isNot(contains('turns')), reason: k.name);
      }
    });

    test('the exclusivity rule is stated, because it decides if it lands', () {
      final main = describeAbilityEffect(
        const AbilityEffect(kind: AbilityEffectKind.frost, chance: 0.5),
      ).join(' ');
      expect(main, contains('mutually exclusive'));
      expect(main, contains('50 %'));
      final debuff = describeAbilityEffect(
        const AbilityEffect(kind: AbilityEffectKind.blind, chance: 0.5),
      ).join(' ');
      expect(debuff, contains('stacks alongside'));
    });

    test('every effect in the list can be described and priced', () {
      // A new entry in the enum with no words or no unit would ship as a blank
      // card — the same "it works but says nothing" bug the building effects had.
      for (final k in AbilityEffectKind.values) {
        expect(k.label, isNotEmpty, reason: k.name);
        expect(k.emoji, isNotEmpty, reason: k.name);
        expect(k.valueLabel, contains('%'), reason: k.name);
        expect(k.defaultValue, greaterThan(0), reason: k.name);
        if (k.isTimed) {
          expect(k.defaultTurns, greaterThan(0), reason: k.name);
        }
        expect(describeAbilityEffect(AbilityEffect(kind: k)).length,
            greaterThanOrEqualTo(2), reason: k.name);
        expect(summariseAbilityEffect(AbilityEffect(kind: k)),
            contains(k.label), reason: k.name);
      }
    });
  });
  // ── POWER: every effect priced in one unit (user 2026-07-30) ──
  // "gib den einzelnen Effekten je nach stärkegrad auch einen powerwert, damit es
  // vergleichbar wird mit den AP."
  //
  // The hole this closes: effects used to be FLAT surcharges (+8 for a status,
  // whatever it did), so making one stronger or longer was free. These pin that
  // the price now follows the move — and that the scale still lines up with the
  // damage it is compared against.
  group('effect power', () {
    AbilityDef move({
      AbilityKind kind = AbilityKind.damage,
      int power = 0,
      int priority = 0,
      List<AbilityEffect> effects = const [],
    }) => AbilityDef(
      id: 'm',
      name: 'M',
      element: CreatureElement.fire,
      kind: kind,
      target: AbilityTarget.enemy,
      power: power,
      priority: priority,
    ).withEffects(effects);

    test('the scale is anchored on the damage it is compared with', () {
      // Power 40 is the basic attack, and the basic attack costs
      // kBasicAttackApCost. If those two ever disagree, "comparable with AP" is
      // just a claim.
      expect(move(power: CombatEngine.basicAttackPower).resolvedApCost,
          kBasicAttackApCost);
    });

    test('twice the magnitude is twice the power', () {
      final weak = const AbilityEffect(kind: AbilityEffectKind.burn, value: 0.05);
      final strong = const AbilityEffect(kind: AbilityEffectKind.burn, value: 0.10);
      expect(strong.power, closeTo(weak.power * 2, 1e-9));
    });

    test('twice the duration is twice the power', () {
      final short = const AbilityEffect(kind: AbilityEffectKind.burn, turns: 2);
      final long = const AbilityEffect(kind: AbilityEffectKind.burn, turns: 4);
      expect(long.power, closeTo(short.power * 2, 1e-9));
    });

    test('half the chance is half the power', () {
      final sure = const AbilityEffect(kind: AbilityEffectKind.burn, chance: 1);
      final maybe = const AbilityEffect(kind: AbilityEffectKind.burn, chance: 0.5);
      expect(maybe.power, closeTo(sure.power / 2, 1e-9));
    });

    test('a longer, surer, heavier effect really costs more AP', () {
      // The exact abuse the flat surcharge allowed: same power, same slot, nine
      // times the burn, and it used to be the same 4 AP.
      final standard = move(power: 50, effects: const [
        AbilityEffect(kind: AbilityEffectKind.burn, chance: 0.3),
      ]);
      final monstrous = move(power: 50, effects: const [
        AbilityEffect(
          kind: AbilityEffectKind.burn,
          chance: 1,
          turns: 9,
          value: 0.25,
        ),
      ]);
      expect(monstrous.totalPower, greaterThan(standard.totalPower * 5));
      expect(monstrous.resolvedApCost, greaterThan(standard.resolvedApCost));
      // And it is not silently clamped mid-way any more: a status move can now
      // reach the top of the AP scale, which is the honest answer.
      expect(monstrous.resolvedApCost, kMaxActionPoints);
    });

    test('a COST has negative power and makes the move cheaper', () {
      final plain = move(power: 90);
      final withRecoil = move(power: 90, effects: const [
        AbilityEffect(kind: AbilityEffectKind.recoil, value: 0.33),
      ]);
      expect(withRecoil.effects.single.power, lessThan(0));
      expect(withRecoil.totalPower, lessThan(plain.totalPower));
      expect(withRecoil.resolvedApCost,
          lessThanOrEqualTo(plain.resolvedApCost));
    });

    test('poison is priced on its ESCALATING total, not value × turns', () {
      // 6 % then 8 % then 10 % — its shape is the catalog's, so a flat
      // value × turns would under-price every poison in the game.
      const p = AbilityEffect(kind: AbilityEffectKind.poison, turns: 3);
      final flat = p.resolvedValue * 3 * AbilityEffectKind.poison.powerCoefficient;
      expect(p.power, greaterThan(flat));
    });

    test('a default effect still prices near the old flat surcharge', () {
      // The calibration promise: existing content barely moves. A typical
      // authored status (30 % chance, catalog strength) used to add 8.
      const e = AbilityEffect(kind: AbilityEffectKind.burn, chance: 0.3);
      expect(e.power, closeTo(9, 3));
    });

    test('every effect has a power, and only the costs are negative', () {
      for (final k in AbilityEffectKind.values) {
        final p = AbilityEffect(kind: k).power;
        expect(p, isNot(0), reason: '${k.name} is priced at nothing');
        expect(p < 0, k.isCost, reason: '${k.name} has the wrong sign');
      }
    });

    test('priority is still paid for', () {
      expect(move(power: 50, priority: 1).resolvedApCost,
          greaterThan(move(power: 50).resolvedApCost));
    });
  });

  // ── The Pokémon-flavoured additions (user 2026-07-30) ──
  // "Gerne darfst du noch weitere Effekte hinzufügen, welche an Pokemon angelehnt
  // sind, aber die aktuellen Monster noch gar nicht verwenden."
  //
  // Each one has to actually DO something in the engine — an effect the form can
  // author and the fight ignores is worse than no effect at all.
  group('the new effects', () {
    test('sleep steals turns at its own chance', () {
      final t = _mob();
      t.applyMainStatus(MainStatusKind.sleep);
      expect(t.mainStatusTurnsRemaining, mainStatusDuration(MainStatusKind.sleep));
      var skips = 0;
      final rng = math.Random(11);
      for (var i = 0; i < 400; i++) {
        if (t.rollSkipTurn(rng)) skips++;
      }
      expect(skips / 400, closeTo(statusSkipChance(MainStatusKind.sleep), 0.06));
      // It is a MAIN status, so it cannot be doubled up with a freeze.
      t.applyMainStatus(MainStatusKind.frost);
      expect(t.mainStatus, MainStatusKind.sleep);
    });

    test('weaken cuts the target\'s attack, on top of a burn\'s own sap', () {
      final t = _mob();
      final base = t.effectiveAttack;
      t.applySecondaryDebuff(SecondaryDebuffKind.attackDown, value: 0.5);
      expect(t.effectiveAttack, closeTo(base * 0.5, 1e-9));
      t.applyMainStatus(MainStatusKind.burn);
      expect(
        t.effectiveAttack,
        closeTo(base * 0.5 * statusAttackMult(MainStatusKind.burn), 1e-9),
      );
    });

    test('expose cuts the target\'s defense', () {
      final t = _mob();
      final base = t.effectiveDefense;
      t.applySecondaryDebuff(SecondaryDebuffKind.defenseDown, value: 0.4);
      expect(t.effectiveDefense, closeTo(base * 0.6, 1e-9));
      // Two turns by default, then gone.
      t.tickStatusEndOfRound();
      t.tickStatusEndOfRound();
      expect(t.effectiveDefense, closeTo(base, 1e-9));
    });

    test('regen heals on every tick and then expires', () {
      final t = _mob(hp: 400);
      t.hp = 100;
      t.applyRegen(turns: 3, value: 0.1);
      for (var i = 0; i < 3; i++) {
        t.tickStatusEndOfRound();
        expect(t.lastRegenHeal, 40, reason: 'tick $i');
      }
      expect(t.hp, 220);
      t.tickStatusEndOfRound();
      expect(t.lastRegenHeal, 0, reason: 'expired');
    });

    test('regen never overheals, and a K.O.\'d monster is not revived', () {
      final t = _mob(hp: 200);
      t.hp = 190;
      t.applyRegen(turns: 2, value: 0.5);
      t.tickStatusEndOfRound();
      expect(t.hp, 200);
      final dead = _mob(hp: 200)..hp = 0;
      dead.applyRegen(turns: 2, value: 0.5);
      dead.tickStatusEndOfRound();
      expect(dead.hp, 0);
    });

    test('recoil bites the user in proportion to the damage it dealt', () {
      final attacker = _mob(id: 'a', hp: 500);
      final target = _mob(id: 'd', hp: 500);
      final engine = CombatEngine(
        players: [attacker],
        enemies: [target],
        rng: math.Random(5),
      );
      attacker.ap = 8;
      final before = attacker.hp;
      engine.useAbility(
        attacker,
        AbilityDef(
          id: 'r',
          name: 'Double-Edge',
          element: CreatureElement.neutral,
          kind: AbilityKind.damage,
          target: AbilityTarget.enemy,
          power: 90,
          recoilValue: 0.5,
        ),
        target,
      );
      final dealt = 500 - target.hp;
      expect(dealt, greaterThan(0));
      expect(before - attacker.hp, (dealt * 0.5).round());
    });

    test('the engine really starts a regen from a heal move', () {
      final healer = _mob(id: 'h', hp: 300);
      final foe = _mob(id: 'f');
      final engine = CombatEngine(
        players: [healer],
        enemies: [foe],
        rng: math.Random(2),
      );
      healer.ap = 8;
      healer.hp = 100;
      engine.useAbility(
        healer,
        AbilityDef(
          id: 'w',
          name: 'Wish',
          element: CreatureElement.light,
          kind: AbilityKind.heal,
          target: AbilityTarget.self,
          healPct: 0.1,
          regenValue: 0.05,
          regenTurns: 4,
        ),
        healer,
      );
      expect(healer.regenTurnsRemaining, 4);
      expect(healer.regenValue, closeTo(0.05, 1e-9));
    });

    test('the new effects round-trip through the row', () {
      final def = AbilityDef(
        id: 'x',
        name: 'X',
        element: CreatureElement.plant,
        kind: AbilityKind.damage,
        target: AbilityTarget.enemy,
        power: 60,
      ).withEffects(const [
        AbilityEffect(kind: AbilityEffectKind.sleep, chance: 0.4, turns: 3),
        AbilityEffect(kind: AbilityEffectKind.defenseDown, chance: 0.8),
        AbilityEffect(kind: AbilityEffectKind.recoil, value: 0.2),
      ]);
      final back = AbilityDef.fromDefRow(def.toDefRow());
      expect(back.inflictMain, MainStatusKind.sleep);
      expect(back.inflictMainTurns, 3);
      expect(back.inflictDebuff, SecondaryDebuffKind.defenseDown);
      expect(back.recoilValue, closeTo(0.2, 1e-9));
      expect(back.effects.map((e) => e.kind), [
        AbilityEffectKind.sleep,
        AbilityEffectKind.defenseDown,
        AbilityEffectKind.recoil,
      ]);
    });

    test('no CURRENT monster uses them — they are new content to author', () {
      // The user asked for effects "welche die aktuellen Monster noch gar nicht
      // verwenden": nothing in the bundled content references them, so adding
      // them changed no existing fight. (kAbilityDefs is DB-loaded and empty in
      // tests, which is exactly the point: there is no bundled ability content.)
      expect(kAbilityDefs, isEmpty);
    });
  });
  // ── The AP RULES themselves (user 2026-07-30, on review: "überprüfen, ob deine
  // AP Regeln umgesetzt werden bezüglich der Power. Ich sehe noch einige
  // Fehler") ──
  //
  // Four things were wrong and each one is a test here: the exchange rate and the
  // priority price were literals no dial could reach, the buff dial had gone
  // inert, and power above what the biggest AP pool can pay for was silently
  // free again.
  group('the AP rules', () {
    tearDown(GameTuning.i.debugClear);

    AbilityDef move(int power, {int prio = 0, int ap = 0, List<AbilityEffect> fx = const []}) =>
        AbilityDef(
          id: 'm',
          name: 'M',
          element: CreatureElement.fire,
          kind: AbilityKind.damage,
          target: AbilityTarget.enemy,
          power: power,
          priority: prio,
          apCost: ap,
        ).withEffects(fx);

    test('the exchange rate is a DIAL, and it really moves the price', () {
      expect(move(65).resolvedApCost, (65 / kPowerPerAp).round());
      GameTuning.i.set(Dials.powerPerAp, 26);
      expect(move(65).resolvedApCost, (65 / 26).round());
      // And the ceiling on what can be priced at all moves with it.
      expect(kMaxPricedPower, kMaxActionPoints * 26);
    });

    test('priority is priced through the same rate, off its own dial', () {
      final base = move(50).totalPower;
      expect(move(50, prio: 2).resolvedApCost,
          ((base + 2 * kPriorityPower) / kPowerPerAp).round());
      GameTuning.i.set(Dials.priorityPower, 60);
      // …up to the pool, which is where every price stops (see the pricing-out
      // test below).
      expect(move(50, prio: 2).resolvedApCost,
          ((base + 120) / kPowerPerAp).round().clamp(2, kMaxActionPoints));
    });

    test('the BUFF dial is a floor, not a fixed price any more', () {
      AbilityDef buff(List<AbilityEffect> fx) => AbilityDef(
        id: 'b',
        name: 'B',
        element: CreatureElement.light,
        kind: AbilityKind.buff,
        target: AbilityTarget.self,
      ).withEffects(fx);
      GameTuning.i.set(Dials.buffApCost, 4);
      // A stock buff sits on the floor…
      expect(buff(const [AbilityEffect(kind: AbilityEffectKind.rage)]).resolvedApCost, 4);
      // …and a big one climbs off it. Before the fix both were the dial's value,
      // which made the dial say nothing about any buff that had an effect.
      expect(
        buff(const [
          AbilityEffect(kind: AbilityEffectKind.haste, turns: 4, value: 0.6),
        ]).resolvedApCost,
        greaterThan(4),
      );
    });

    test('a non-buff has its own floor dial', () {
      GameTuning.i.set(Dials.minAbilityApCost, 3);
      expect(move(1).resolvedApCost, 3);
    });

    test('power above what anyone can PAY is reported, not hidden', () {
      // The saturation is structural — nobody can spend more than the final
      // form's whole pool — so the honest move is to name it. Silence here is the
      // old flat-surcharge hole one step further out.
      final ok = move(kMaxPricedPower - 10);
      final over = move(kMaxPricedPower + 200);
      expect(ok.isOverPricedOut, isFalse);
      expect(over.isOverPricedOut, isTrue);
      expect(over.resolvedApCost, kMaxActionPoints);
      expect(ok.resolvedApCost, lessThanOrEqualTo(kMaxActionPoints));
      // An explicitly priced move is the author overruling the formula, so it is
      // not "priced out" — it has no derived price to lose.
      expect(move(kMaxPricedPower + 200, ap: 5).isOverPricedOut, isFalse);
    });

    test('the flat surcharges and the 4-AP status clamp are really gone', () {
      // Two moves that the old formula priced identically: +8 for a status, then
      // clamped to 4 whatever it did.
      final mild = move(50, fx: const [
        AbilityEffect(kind: AbilityEffectKind.burn, chance: 0.2, turns: 2, value: 0.03),
      ]);
      final harsh = move(50, fx: const [
        AbilityEffect(kind: AbilityEffectKind.burn, chance: 1, turns: 6, value: 0.15),
      ]);
      expect(harsh.resolvedApCost, greaterThan(mild.resolvedApCost));
      expect(harsh.resolvedApCost, greaterThan(4));
    });

    test('an explicit AP is clamped to what a monster could hold', () {
      expect(move(50, ap: 99).resolvedApCost, kMaxActionPoints);
      expect(move(50, ap: 1).resolvedApCost, 1);
    });

    test('the basic attack stays the anchor of the whole scale', () {
      // If these two ever drift, "power is comparable with AP" is a claim with
      // nothing behind it: the free attack IS 40 power and DOES cost its dial.
      expect(move(CombatEngine.basicAttackPower).resolvedApCost,
          kBasicAttackApCost);
    });
  });
}
