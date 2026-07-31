import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/ability_def.dart';
import 'package:boddygame/features/creatures/models/combatant.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/species_def.dart';
import 'package:boddygame/features/creatures/models/status_effects.dart';
import 'package:boddygame/features/creatures/services/combat_engine.dart';
import 'package:boddygame/features/creatures/services/combat_tuning.dart';
import 'package:boddygame/features/creatures/services/overworld_path.dart';

Combatant make({
  required String id,
  bool player = true,
  int speed = 10,
  int hp = 200,
  int attack = 60,
  int defense = 30,
  int level = 10,
  int stage = 0,
  CreatureElement element = CreatureElement.fire,
  List<AbilityDef> abilities = const [],
}) => Combatant(
  id: id,
  name: id,
  element: element,
  rarity: CreatureRarity.common,
  isPlayerSide: player,
  level: level,
  stage: stage,
  stats: {
    CreatureStat.hp: hp,
    CreatureStat.attack: attack,
    CreatureStat.defense: defense,
    CreatureStat.speed: speed,
    CreatureStat.catchRate: 5,
  },
  abilities: abilities,
);

/// An engine whose combatants start on FULL pools.
///
/// Since the 2026-07-20 AP redesign a battle opens deliberately lean (2 AP for
/// the first actor, 3 for the other) — below an attack's cost. That opening is
/// exercised by the `action points` group, which builds its engines raw. Every
/// other test here is about damage, status, reserves or types and just needs
/// its actors able to act, so it arms them instead of choreographing a bank-up
/// that has nothing to do with what it asserts.
CombatEngine armedEngine({
  required List<Combatant> players,
  required List<Combatant> enemies,
  math.Random? rng,
}) {
  final engine = CombatEngine(players: players, enemies: enemies, rng: rng);
  for (final c in [...players, ...enemies]) {
    c.ap = maxActionPointsForStage(c.stage);
  }
  return engine;
}

void main() {
  // CombatTuning is a global singleton; restore defaults so a dial test can't
  // bleed into the others.
  tearDown(() => CombatTuning().resetToDefaults());

  group('combat tuning dials feed the damage formula', () {
    test('higher damage scale hits harder, lower hits softer', () {
      int hit(double scale) {
        CombatTuning().damageScale = scale;
        final a = make(id: 'a');
        final b = make(id: 'b', player: false);
        final engine = armedEngine(
          players: [a],
          enemies: [b],
          rng: math.Random(1),
        );
        engine.basicAttack(a, b);
        engine.dispose();
        return b.maxHp - b.hp;
      }
      expect(hit(1.2), greaterThan(hit(0.3)));
    });

    test('higher defense weight blocks more damage', () {
      int hit(double w) {
        CombatTuning().defenseWeight = w;
        final a = make(id: 'a');
        final b = make(id: 'b', player: false, defense: 60);
        final engine = armedEngine(
          players: [a],
          enemies: [b],
          rng: math.Random(1),
        );
        engine.basicAttack(a, b);
        engine.dispose();
        return b.maxHp - b.hp;
      }
      // w=0 → defense ignored (attack dominates) → more damage than w=3.
      expect(hit(0.0), greaterThan(hit(3.0)));
    });
  });

  test('one hit can never take a full-HP combatant out (no one-shots)', () {
    // User requirement 2026-07-17: two starters must NEVER one-shot each
    // other, however the STAB × type × crit stack lands. An absurdly strong
    // attacker vs a fragile full-HP target still leaves it alive, and the
    // hit never exceeds kMaxHitHpFraction of max HP.
    for (var seed = 0; seed < 40; seed++) {
      final glass = make(id: 'glass', hp: 30, defense: 1, speed: 5);
      final monster = make(
        id: 'monster',
        player: false,
        attack: 9999,
        speed: 99,
      );
      final engine = armedEngine(
        players: [glass],
        enemies: [monster],
        rng: math.Random(seed),
      );
      // Monster is faster — its opening strike is the very first action.
      engine.performAutoAction();
      expect(glass.alive, isTrue, reason: 'seed $seed: one-shot from full HP');
      expect(
        glass.maxHp - glass.hp,
        lessThanOrEqualTo(
          (glass.maxHp * CombatEngine.kMaxHitHpFraction).floor(),
        ),
        reason: 'seed $seed: single hit exceeded the cap',
      );
      engine.dispose();
    }
  });

  // ── Simultaneous field (user design 2026-07-27) ───────────────────────
  // "Wenn pro Seite mehrere Monster kämpfen, kämpfen diese wie in einem jrpg
  // gleichzeitig … Maximal 3 Monster können pro Seite gleichzeitig kämpfen."
  //
  // These replace the 1v1 reserve group (2026-07-17), which asserted the exact
  // opposite: that a party fought one monster at a time and the rest were an
  // untargetable bench. That model is gone, so the tests that pinned it down
  // had to go with it.
  group('the field holds three a side', () {
    test('all three take turns — the bench does not', () {
      final p = [
        make(id: 'p1', speed: 20),
        make(id: 'p2', speed: 20),
        make(id: 'p3', speed: 20),
        make(id: 'p4', speed: 999), // reserve, and the fastest of the lot
      ];
      final e1 = make(id: 'e1', player: false, speed: 10);
      final engine = armedEngine(players: p, enemies: [e1]);

      expect(engine.fieldPlayers, [p[0], p[1], p[2]]);
      expect(engine.benchedPlayers, [p[3]]);
      final order = engine.forecast(8);
      // The three on the field are all in the queue…
      for (final c in [p[0], p[1], p[2], e1]) {
        expect(order.contains(c), isTrue, reason: '${c.name} misses its turns');
      }
      // …and the reserve is not, however fast it is.
      expect(order.contains(p[3]), isFalse);
    });

    test('a fourth enemy steps in the moment a slot opens', () {
      final p = make(id: 'p', attack: 9999, speed: 99);
      final e = [
        make(id: 'e1', player: false, speed: 1)..hp = 1,
        make(id: 'e2', player: false, speed: 1),
        make(id: 'e3', player: false, speed: 1),
        make(id: 'e4', player: false, speed: 1),
      ];
      final engine = armedEngine(players: [p], enemies: e);
      expect(engine.fieldEnemies, [e[0], e[1], e[2]]);

      var g = 0;
      while (e[0].alive && g++ < 20) {
        engine.basicAttack(p, e[0]);
      }
      expect(e[0].alive, isFalse);
      expect(engine.outcome, isNull);
      // No pause, no pick: the pack fills its own gap (user 2026-07-27 — the
      // enemy bench is unlimited and "springt direkt ein").
      expect(engine.fieldEnemies.contains(e[3]), isTrue);
      expect(engine.fieldEnemies.length, 3);
    });

    test('victory only when the whole enemy roster is down', () {
      final p = make(id: 'p', attack: 9999, speed: 99);
      final e = [
        for (var i = 0; i < 4; i++)
          make(id: 'e$i', player: false, speed: 1)..hp = 1,
      ];
      final engine = armedEngine(players: [p], enemies: e);
      var g = 0;
      while (engine.outcome == null && g++ < 60) {
        final target = engine.fieldEnemies.first;
        engine.basicAttack(p, target);
        // p only holds so much AP; hand the turn back when it runs dry.
        if (!engine.isPlayerTurn) engine.performAutoAction();
      }
      expect(engine.outcome, CombatOutcome.victory);
      expect(e.every((c) => !c.alive), isTrue);
    });

    test('an empty player slot pauses for a reserve, then play resumes', () {
      final p = [
        make(id: 'p1', speed: 1)..hp = 1,
        make(id: 'p2', speed: 1),
        make(id: 'p3', speed: 1),
        make(id: 'p4', speed: 1), // the reserve
      ];
      final e = make(id: 'e', player: false, attack: 9999, speed: 99);
      final engine = armedEngine(players: p, enemies: [e]);
      var g = 0;
      while (p[0].alive && g++ < 20) {
        engine.basicAttack(e, p[0]);
      }
      expect(p[0].alive, isFalse);
      expect(engine.outcome, isNull);
      expect(engine.needsPlayerSwitch, isTrue,
          reason: 'the slot is empty and p4 can fill it');
      expect(engine.switchActivePlayer(3), isNull);
      expect(engine.needsPlayerSwitch, isFalse);
      // It took the FALLEN monster's slot, not somebody else's.
      expect(engine.playerField[0], p[3]);
      expect(engine.fieldPlayers.length, 3);
    });

    test('a slot nobody can fill is simply left empty', () {
      final p = [make(id: 'p1', speed: 1)..hp = 1, make(id: 'p2', speed: 1)];
      final e = make(id: 'e', player: false, attack: 9999, speed: 99);
      final engine = armedEngine(players: p, enemies: [e]);
      var g = 0;
      while (p[0].alive && g++ < 20) {
        engine.basicAttack(e, p[0]);
      }
      expect(engine.needsPlayerSwitch, isFalse, reason: 'no reserve exists');
      expect(engine.outcome, isNull, reason: 'p2 is still standing');
      expect(engine.fieldPlayers, [p[1]]);
    });

    test('defeat only when the whole player roster is down', () {
      final p1 = make(id: 'p1', speed: 1)..hp = 1;
      final e = make(id: 'e', player: false, attack: 9999, speed: 99);
      final engine = armedEngine(players: [p1], enemies: [e]);
      var g = 0;
      while (engine.outcome == null && g++ < 20) {
        engine.basicAttack(e, p1);
      }
      expect(engine.outcome, CombatOutcome.defeat);
    });

    test('a voluntary switch costs no turn — the reserve still acts', () {
      final p1 = make(id: 'p1', speed: 50);
      final bench = make(id: 'bench', speed: 5);
      final e = make(id: 'e', player: false, speed: 1);
      // Three on the field, so `bench` really is a reserve.
      final engine = armedEngine(
        players: [p1, make(id: 'p2', speed: 1), make(id: 'p3', speed: 1), bench],
        enemies: [e],
      );
      expect(engine.isPlayerTurn, isTrue);
      expect(engine.currentActor, p1);
      // Swap the ACTING monster out — the reserve inherits its slot and its
      // turn, so it is still the player's move.
      expect(engine.switchActivePlayer(3), isNull);
      expect(engine.playerField[0], bench, reason: 'it took p1\'s slot');
      expect(engine.isPlayerTurn, isTrue);
      expect(engine.currentActor, bench);
    });

    test('a monster already on the field cannot be switched in', () {
      final p1 = make(id: 'p1', speed: 50);
      final p2 = make(id: 'p2', speed: 5);
      final e = make(id: 'e', player: false, speed: 1);
      final engine = armedEngine(players: [p1, p2], enemies: [e]);
      expect(engine.switchActivePlayer(1), isNotNull,
          reason: 'p2 is standing right there');
    });
  });

  test('the party is exactly a full field plus a full reserve', () {
    // The user's own numbers (2026-07-27): 3 fight at once, "max. 3 Reserve".
    // kMaxPartySize is what the linear path grows the party TO, so the two have
    // to stay locked together — raising one without the other silently means
    // either dead reserve slots or a party that cannot fill the field.
    expect(CombatEngine.kFieldSlots, 3);
    expect(kMaxPartySize, CombatEngine.kFieldSlots * 2);
  });

  group('targeting a crowded field', () {
    test('a strike hits the monster it was aimed at, not the first one', () {
      final p = make(id: 'p', attack: 200, speed: 99);
      final e = [
        make(id: 'e1', player: false, speed: 1),
        make(id: 'e2', player: false, speed: 1),
        make(id: 'e3', player: false, speed: 1),
      ];
      final engine = armedEngine(players: [p], enemies: e, rng: math.Random(1));
      engine.basicAttack(p, e[2]);
      expect(e[2].hp, lessThan(e[2].maxHp));
      expect(e[0].hp, e[0].maxHp);
      expect(e[1].hp, e[1].maxHp);
    });

    test('allEnemies finally means all of them', () {
      // Under the 1v1 model this resolved to the single active opponent, so a
      // spread move was a single-target move with a grander name.
      final blast = AbilityDef(
        id: 'blast',
        name: 'Blast',
        element: CreatureElement.shadow,
        kind: AbilityKind.damage,
        target: AbilityTarget.allEnemies,
        power: 40,
      );
      final p = make(id: 'p', abilities: [blast], stage: 2, speed: 99);
      final e = [
        for (var i = 0; i < 3; i++) make(id: 'e$i', player: false, speed: 1),
      ];
      final engine = armedEngine(players: [p], enemies: e, rng: math.Random(2));
      expect(engine.useAbility(p, blast, e[0]), isNull);
      for (final c in e) {
        expect(c.hp, lessThan(c.maxHp), reason: '${c.name} was spared');
      }
    });

    test('a stale target falls back instead of fizzling the move', () {
      final p = make(id: 'p', attack: 400, speed: 99);
      final e = [
        make(id: 'e1', player: false, speed: 1),
        make(id: 'e2', player: false, speed: 1),
      ];
      final engine = armedEngine(players: [p], enemies: e, rng: math.Random(3));
      e[0].hp = 0; // fell to an ally a moment ago; the UI still points at it
      final hit = AbilityDef(
        id: 'hit',
        name: 'Hit',
        element: CreatureElement.shadow,
        kind: AbilityKind.damage,
        target: AbilityTarget.enemy,
        power: 30,
      );
      expect(engine.useAbility(p, hit, e[0]), isNull);
      expect(e[1].hp, lessThan(e[1].maxHp));
    });
  });

  test('faster combatant acts first and more often', () {
    final fast = make(id: 'fast', speed: 20);
    final slow = make(id: 'slow', player: false, speed: 10);
    final engine = armedEngine(players: [fast], enemies: [slow]);

    expect(engine.currentActor, fast);
    final order = engine.forecast(9);
    final fastTurns = order.where((c) => c == fast).length;
    final slowTurns = order.where((c) => c == slow).length;
    // Double speed = double turn frequency.
    expect(fastTurns, greaterThanOrEqualTo(slowTurns * 2 - 1));
  });

  test('basic attack damages and spends AP', () {
    // The battle opens LEAN (user 2026-07-20): the first actor holds
    // kStartApFirst (2), which is below an attack's cost — so it banks a turn
    // first. That opening tempo is the design, not a bug.
    final a = make(id: 'a');
    final b = make(id: 'b', player: false);
    final engine = CombatEngine(
      players: [a],
      enemies: [b],
      rng: math.Random(42),
    );
    expect(engine.turnAp, kStartApFirst);
    engine.basicAttack(a, b);
    expect(b.hp, b.maxHp, reason: '2 AP cannot pay for a 3 AP attack');

    engine.endTurn(); // bank it — b takes its opening turn
    engine.basicAttack(b, a); // b spends its 3 and hands the turn back
    expect(engine.currentActor, a);
    // a regenerated ONTO its banked 2: 2 + 3 = 4 (its stage-0 cap).
    expect(engine.turnAp, maxActionPointsForStage(0));
    engine.basicAttack(a, b);
    expect(b.hp, lessThan(b.maxHp));
    expect(engine.outcome, isNull);
  });

  group('action points (user redesign 2026-07-20)', () {
    test('capacity 4/6/8 and regen 3/4/5 grow with evolution stage', () {
      expect(maxActionPointsForStage(0), 4); // 1st form
      expect(maxActionPointsForStage(1), 6); // 2nd form
      expect(maxActionPointsForStage(2), 8); // 3rd form
      expect(maxActionPointsForStage(9), 8); // clamped past the final stage
      expect(apRegenForStage(0), 3);
      expect(apRegenForStage(1), 4);
      expect(apRegenForStage(2), 5);
      expect(apRegenForStage(9), 5);
      // THE rule the whole redesign rests on: regen sits strictly BELOW
      // capacity, so a full pool can only ever come from holding back.
      for (var s = 0; s < 3; s++) {
        expect(apRegenForStage(s), lessThan(maxActionPointsForStage(s)),
            reason: 'stage $s would refill itself every turn');
      }
    });

    test('the battle opens on 2 AP for the first actor, 3 for the other', () {
      // Equal speed → they strictly alternate (the index epsilon puts the
      // player first). A faster `a` would simply take two turns in a row and
      // never hand over, which is not what this is about.
      final a = make(id: 'a');
      final b = make(id: 'b', player: false);
      final engine = CombatEngine(players: [a], enemies: [b]);
      expect(engine.currentActor, a);
      expect(a.ap, kStartApFirst);
      expect(b.ap, kStartApSecond);
      // ...and the second monster's OWN first turn is that 3, not 3 + regen.
      engine.endTurn();
      expect(engine.currentActor, b);
      expect(engine.turnAp, kStartApSecond);
    });

    test('AP regenerate onto what is left — they are not refilled', () {
      final a = make(id: 'a', stage: 2); // capacity 8, regen 5
      final b = make(id: 'b', player: false, hp: 5000);
      final engine = CombatEngine(players: [a], enemies: [b]);
      expect(a.ap, kStartApFirst);
      engine.endTurn(); // bank the 2
      engine.basicAttack(b, a); // enemy swings, turn comes back
      expect(engine.currentActor, a);
      expect(a.ap, kStartApFirst + apRegenForStage(2),
          reason: 'a refill would have handed it the full 8');
    });

    test('regen stops at the capacity', () {
      final a = make(id: 'a'); // capacity 4, regen 3
      final b = make(id: 'b', player: false, hp: 5000);
      final engine = CombatEngine(players: [a], enemies: [b]);
      for (var i = 0; i < 3; i++) {
        engine.endTurn(); // never spend
        engine.basicAttack(b, a);
      }
      expect(a.ap, maxActionPointsForStage(0));
    });

    test('you can bank AP to afford a move one turn could not pay for', () {
      // The point of the redesign, in one test.
      final big = AbilityDef(
        id: 'big',
        name: 'Big',
        element: CreatureElement.fire,
        kind: AbilityKind.damage,
        target: AbilityTarget.enemy,
        power: 60,
        apCost: 4,
      );
      final a = make(id: 'a', abilities: [big]);
      final b = make(id: 'b', player: false, hp: 5000);
      final engine = CombatEngine(players: [a], enemies: [b]);
      expect(engine.useAbility(a, big, b), isNotNull,
          reason: '2 AP on the opening turn cannot pay 4');
      engine.endTurn();
      engine.basicAttack(b, a);
      expect(a.ap, 4); // 2 banked + 3 regen, capped at 4
      expect(engine.useAbility(a, big, b), isNull);
      expect(a.ap, 0);
    });

    test('buffs and debuffs are cheap — play them alongside an attack', () {
      // User 2026-07-17: buffs/debuffs should be worth playing, so they cost
      // little — a buff + an attack fits inside one turn (2 + 3 = 5).
      final buff = AbilityDef(
        id: 'rage',
        name: 'Rage',
        element: CreatureElement.shadow,
        kind: AbilityKind.buff,
        target: AbilityTarget.self,
        selfBuff: SelfBuffKind.rage,
      );
      final debuffMove = AbilityDef(
        id: 'weaken',
        name: 'Weaken',
        element: CreatureElement.shadow,
        kind: AbilityKind.damage,
        target: AbilityTarget.enemy,
        power: 20,
        inflictDebuff: SecondaryDebuffKind.speedDown,
      );
      final bigHit = AbilityDef(
        id: 'blast',
        name: 'Blast',
        element: CreatureElement.shadow,
        kind: AbilityKind.damage,
        target: AbilityTarget.enemy,
        power: 90,
      );
      // A buff is a flat cheap cost; a debuff move is capped mid; a big pure
      // attack is expensive.
      expect(CombatEngine.abilityApCost(buff), kBuffApCost);
      expect(CombatEngine.abilityApCost(debuffMove), lessThanOrEqualTo(4));
      expect(
        CombatEngine.abilityApCost(bigHit),
        greaterThan(CombatEngine.abilityApCost(debuffMove)),
      );
    });

    test('a banked pool buys two attacks in one turn', () {
      final a = make(id: 'a', stage: 2); // capacity 8, regen 5
      final b = make(id: 'b', player: false, hp: 5000);
      final engine = CombatEngine(players: [a], enemies: [b]);
      engine.endTurn(); // bank the opening 2
      engine.basicAttack(b, a);
      expect(engine.turnAp, 7); // 2 + 5
      engine.basicAttack(a, b); // 7 → 4
      expect(engine.currentActor, a, reason: 'still a\'s turn, 4 AP left');
      engine.basicAttack(a, b); // 4 → 1
      expect(engine.currentActor, b, reason: '1 AP < 3, a\'s turn ends');
    });

    test('End Turn banks the unspent AP instead of forfeiting them', () {
      // The old rule threw the remainder away, which made holding back
      // pointless — the exact thing this redesign removes.
      final a = make(id: 'a', stage: 2);
      final b = make(id: 'b', player: false);
      final engine = CombatEngine(players: [a], enemies: [b]);
      expect(engine.isPlayerTurn, isTrue);
      final before = a.ap;
      engine.endTurn();
      expect(engine.currentActor, b);
      expect(a.ap, before, reason: 'unspent AP are kept, not lost');
    });

    test('a switch is paid by the monster leaving; the reserve keeps its own',
        () {
      final a = make(id: 'a', stage: 2, speed: 50);
      // Three on the field, so `b` is a genuine reserve (the field holds 3 a
      // side since 2026-07-27).
      final filler1 = make(id: 'f1', speed: 1);
      final filler2 = make(id: 'f2', speed: 1);
      final b = make(id: 'b', stage: 2);
      final e = make(id: 'e', player: false, speed: 1);
      final engine = CombatEngine(players: [a, filler1, filler2, b], enemies: [e]);
      expect(engine.currentActor, a);
      expect(a.ap, kStartApFirst);
      final ok = engine.switchActivePlayer(3);
      expect(ok, isNull);
      expect(engine.playerField[0], b);
      expect(a.ap, kStartApFirst - kSwitchApCost,
          reason: 'the outgoing monster pays out of its own pool');
      expect(b.ap, kStartApSecond,
          reason: 'the reserve arrives on its own AP — nothing is handed over');
    });
  });

  test('type matrix: 1.5 super-effective beats 0.5 resisted (STAB held equal)', () {
    final fireMove = AbilityDef(
      id: 'fire_move',
      name: 'Fire Move',
      element: CreatureElement.fire,
      kind: AbilityKind.damage,
      target: AbilityTarget.enemy,
      power: 80,
    );

    int damageAgainst(CreatureElement targetElement) {
      // Attacker is ALSO fire, so STAB (1.5x) applies identically in both
      // calls — only the target's element (and thus the type multiplier)
      // differs between the two measurements.
      // Stage 2 → 7 AP, enough for the power-80 move (6 AP).
      final attacker = make(id: 'atk', abilities: [fireMove], stage: 2);
      final target = make(id: 'tgt', player: false, element: targetElement, hp: 5000);
      final engine = armedEngine(
        players: [attacker],
        enemies: [target],
        rng: math.Random(7), // same seed -> same variance/crit both runs
      );
      final error = engine.useAbility(attacker, fireMove, target);
      expect(error, isNull);
      return 5000 - target.hp;
    }

    final vsPlant = damageAgainst(CreatureElement.plant); // 1.5x
    final vsWater = damageAgainst(CreatureElement.water); // 0.5x
    expect(vsPlant, greaterThan(vsWater));
    // 1.5x vs 0.5x with identical variance/crit -> factor 3 up to floor
    // rounding (user lowered advantage from 2.0 to 1.5, 2026-07-17).
    expect(vsPlant, closeTo(vsWater * 3, 2.99));
  });

  test('Licht and Schatten both hit each other hard and resist themselves', () {
    // Advantage is 1.5 (not 2.0) since 2026-07-17; self-resist stays 0.5.
    expect(CreatureElement.light.multiplierVs(CreatureElement.shadow), 1.5);
    expect(CreatureElement.shadow.multiplierVs(CreatureElement.light), 1.5);
    expect(CreatureElement.light.multiplierVs(CreatureElement.light), 0.5);
    expect(CreatureElement.shadow.multiplierVs(CreatureElement.shadow), 0.5);
  });

  group('ability AP cost (user 2026-07-19)', () {
    test('an explicit apCost overrides the derived cost (clamped to the cap)',
        () {
      const powerful = AbilityDef(
        id: 'x',
        name: 'X',
        element: CreatureElement.shadow,
        kind: AbilityKind.damage,
        target: AbilityTarget.enemy,
        power: 200,
      );
      // Auto (apCost 0): power 200 derives the ceiling, which the 2026-07-20
      // AP redesign raised to the final form's capacity.
      expect(CombatEngine.abilityApCost(powerful), kMaxActionPoints);
      // Explicit wins.
      expect(CombatEngine.abilityApCost(powerful.withApCost(3)), 3);
      // Explicit is clamped into 1..kMaxActionPoints.
      expect(CombatEngine.abilityApCost(powerful.withApCost(99)),
          kMaxActionPoints);
    });

    test('a starting ability (unlockStage 0) is capped at 4 AP', () {
      kAbilityDefs['nuke'] = const AbilityDef(
        id: 'nuke',
        name: 'Nuke',
        element: CreatureElement.shadow,
        kind: AbilityKind.damage,
        target: AbilityTarget.enemy,
        power: 200, // auto-derives 7 AP
      );
      addTearDown(() => kAbilityDefs.remove('nuke'));

      const species = SpeciesDef(
        id: 'sp',
        name: 'Sp',
        element: CreatureElement.shadow,
        rarity: CreatureRarity.common,
        stats: {},
        stages: [
          SpeciesStage(name: 'a'),
          SpeciesStage(name: 'b'),
          SpeciesStage(name: 'c'),
        ],
        abilities: [SpeciesAbility(abilityId: 'nuke', unlockStage: 0)],
      );

      // Base form (stage 0 → 4 AP): the power-200 starting move is capped to 4.
      final base = Combatant.fromSpecies(species, level: 1, id: 'c');
      expect(base.abilities.single.resolvedApCost, 4);

      // Even on the final evolution the SAME starting move stays capped at its
      // unlock stage's 4 AP.
      final evolved = Combatant.fromSpecies(species, level: 99, id: 'c');
      expect(evolved.abilities.single.resolvedApCost, 4);
    });
  });

  test('ability requires AP and reports an error instead of acting', () {
    // Power 100 → 7 AP; a base-stage monster only has 4, so it's refused.
    final pricey = AbilityDef(
      id: 'pricey',
      name: 'Pricey',
      element: CreatureElement.shadow,
      kind: AbilityKind.damage,
      target: AbilityTarget.enemy,
      power: 100,
    );
    final a = make(id: 'a', abilities: [pricey]);
    final b = make(id: 'b', player: false);
    final engine = armedEngine(players: [a], enemies: [b]);

    final error = engine.useAbility(a, pricey, b);

    expect(error, isNotNull);
    expect(b.hp, b.maxHp); // nothing happened
    expect(engine.currentActor, isNot(b)); // turn NOT consumed
  });

  test('haste buff makes a slow combatant overtake in the forecast', () {
    final slowAlly = make(id: 'slow', speed: 10);
    final enemy = make(id: 'enemy', player: false, speed: 15);
    final engine = armedEngine(players: [slowAlly], enemies: [enemy]);

    final before = engine.forecast(6).where((c) => c == slowAlly).length;
    slowAlly.applySelfBuff(SelfBuffKind.haste);
    final after = engine.forecast(6).where((c) => c == slowAlly).length;

    expect(after, greaterThan(before));
  });

  test('victory when all enemies die; the reward is the kill formula', () {
    final a = make(id: 'a', attack: 999);
    final weak = make(id: 'weak', player: false, hp: 1, defense: 0);
    final engine = armedEngine(
      players: [a],
      enemies: [weak],
      rng: math.Random(1),
    );

    engine.basicAttack(a, weak);

    expect(engine.outcome, CombatOutcome.victory);
    // Read through the CONFIG rather than restating its numbers — the curve
    // is dev-tunable, and a literal here only ever pinned the day it was
    // written (it said 9 · L^2.3 long after the default moved to L^1.3).
    expect(engine.totalXpReward, kXpBalance.killXp(weak.level).round());
  });

  test('heal never exceeds max HP', () {
    // 1v1 reserve model: the only ally on the field is the caster itself, so a
    // heal is a self-heal.
    final mend = AbilityDef(
      id: 'mend',
      name: 'Mend',
      element: CreatureElement.shadow,
      kind: AbilityKind.heal,
      target: AbilityTarget.ally,
      healPct: 0.99,
    );
    final healer = make(id: 'healer', abilities: [mend], stage: 2); // 7 AP
    healer.hp = 50;
    final enemy = make(id: 'enemy', player: false);
    final engine = armedEngine(players: [healer], enemies: [enemy]);

    engine.useAbility(healer, mend, healer);

    expect(healer.hp, healer.maxHp);
  });

  test('lifesteal heals the attacker a fraction of the damage dealt', () {
    final drain = AbilityDef(
      id: 'drain',
      name: 'Drain',
      element: CreatureElement.shadow,
      kind: AbilityKind.damage,
      target: AbilityTarget.enemy,
      power: 80,
      lifestealPct: 0.5,
    );
    final attacker = make(id: 'atk', abilities: [drain], stage: 2); // 7 AP
    attacker.hp = 10;
    final target = make(id: 'tgt', player: false, hp: 500);
    final engine = armedEngine(
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
      element: CreatureElement.shadow,
      kind: AbilityKind.damage,
      target: AbilityTarget.enemy,
      power: 10,
      inflictMain: MainStatusKind.burn,
      inflictMainChance: 1.0,
    );
    final attacker = make(id: 'atk', speed: 20, abilities: [burnMove]);
    final target = make(id: 'tgt', player: false, speed: 10, hp: 1000);
    final engine = armedEngine(
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
    final engine = armedEngine(
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
