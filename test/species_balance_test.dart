import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/ability_def.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/species_def.dart';
import 'package:boddygame/features/creatures/services/species_balance.dart';

SpeciesDef _species(
  String id, {
  CreatureElement element = CreatureElement.fire,
  CreatureRarity rarity = CreatureRarity.common,
  double hp = 60,
  double atk = 45,
  double def = 40,
  double spd = 35,
  List<SpeciesAbility> abilities = const [],
}) => SpeciesDef(
  id: id,
  name: id,
  element: element,
  rarity: rarity,
  stats: {
    CreatureStat.hp: StatCurve(stageBase: [hp, hp * 1.25, hp * 1.5], growth: 2),
    CreatureStat.attack: StatCurve(
      stageBase: [atk, atk * 1.25, atk * 1.5],
      growth: 1.5,
    ),
    CreatureStat.defense: StatCurve(
      stageBase: [def, def * 1.25, def * 1.5],
      growth: 1.3,
    ),
    CreatureStat.speed: StatCurve(
      stageBase: [spd, spd * 1.25, spd * 1.5],
      growth: 1.2,
    ),
  },
  stages: const [
    SpeciesStage(name: 's0'),
    SpeciesStage(name: 's1'),
    SpeciesStage(name: 's2'),
  ],
  abilities: abilities,
);

void main() {
  tearDown(() {
    kAbilityDefs.clear();
    kSpeciesDefs.clear();
  });

  group('meanCombatant', () {
    test('uses the species curve directly — deterministic, no gene roll', () {
      final s = _species('a');
      final c1 = meanCombatant(s, level: 10, isPlayerSide: true);
      final c2 = meanCombatant(s, level: 10, isPlayerSide: true);
      expect(c1.stats, c2.stats);
      // hp = 60 + 2*(10-1) = 78
      expect(c1.stats[CreatureStat.hp], 78);
    });

    test('evolves with level and carries stage-unlocked abilities', () {
      kAbilityDefs['bite'] = const AbilityDef(
        id: 'bite',
        name: 'Bite',
        element: CreatureElement.fire,
        kind: AbilityKind.damage,
        target: AbilityTarget.enemy,
        power: 50,
      );
      final s = SpeciesDef(
        id: 'evo',
        name: 'evo',
        element: CreatureElement.fire,
        rarity: CreatureRarity.common,
        evoLevel1: 20,
        evoLevel2: 40,
        stats: _species('x').stats,
        stages: _species('x').stages,
        abilities: const [
          SpeciesAbility(abilityId: 'bite', unlockStage: 1),
        ],
      );
      expect(meanCombatant(s, level: 10, isPlayerSide: true).stage, 0);
      expect(
        meanCombatant(s, level: 10, isPlayerSide: true).abilities,
        isEmpty,
        reason: 'bite unlocks at stage 1',
      );
      final evolved = meanCombatant(s, level: 25, isPlayerSide: true);
      expect(evolved.stage, 1);
      expect(evolved.abilities.map((a) => a.id), ['bite']);
    });
  });

  group('simulatePairing', () {
    test('a mirror match is a coin flip and deterministic per seed', () {
      final s = _species('mirror');
      final r1 = simulatePairing(s, s, level: 10, runs: 60);
      final r2 = simulatePairing(s, s, level: 10, runs: 60);
      expect(r1.aWinRate, r2.aWinRate, reason: 'same seed, same result');
      expect(r1.aWinRate, closeTo(0.5, 0.2));
      expect(r1.runs, 60);
    });

    test('a much stronger species wins nearly always', () {
      final weak = _species('weak', hp: 40, atk: 30, def: 25, spd: 20);
      final strong = _species('strong', hp: 90, atk: 70, def: 60, spd: 50);
      final r = simulatePairing(strong, weak, level: 10, runs: 40);
      expect(r.aWinRate, greaterThan(0.9));
    });

    test('counts TOTAL actions of both sides and flags the 3-10 band', () {
      final a = _species('a');
      final b = _species('b');
      final r = simulatePairing(a, b, level: 10, runs: 30);
      expect(r.minActions, greaterThan(0));
      expect(r.maxActions, greaterThanOrEqualTo(r.minActions));
      // Every run outside 3..10 must be counted on exactly one side.
      expect(r.tooShort + r.tooLong, lessThanOrEqualTo(r.runs));
    });

    test('type advantage shows up as a win-rate edge', () {
      final fire = _species('fire', element: CreatureElement.fire);
      final plant = _species('plant', element: CreatureElement.plant);
      kAbilityDefs['ember'] = const AbilityDef(
        id: 'ember',
        name: 'Ember',
        element: CreatureElement.fire,
        kind: AbilityKind.damage,
        target: AbilityTarget.enemy,
        power: 55,
      );
      final fireArmed = SpeciesDef(
        id: 'fireArmed',
        name: 'fireArmed',
        element: CreatureElement.fire,
        rarity: CreatureRarity.common,
        stats: fire.stats,
        stages: fire.stages,
        abilities: const [SpeciesAbility(abilityId: 'ember')],
      );
      final r = simulatePairing(fireArmed, plant, level: 10, runs: 60);
      expect(
        r.aWinRate,
        greaterThan(0.55),
        reason: 'STAB + type advantage must beat a mirror-stat plant',
      );
      // …and the ability actually got used, which is what the usage stats
      // exist to prove.
      expect(r.aAbilityUses['ember'] ?? 0, greaterThan(0));
    });
  });

  group('levelToWinHalf', () {
    test('an even matchup needs at most a level or two', () {
      // NOT exactly the base level: the opening-AP rule (first actor starts on
      // 2 AP, the other on 3) gives the player side a small first-mover
      // DISADVANTAGE, so even a mirror match can sit just under 50% and need
      // a level or two. That asymmetry is real and worth this test knowing
      // about — if this ever balloons, the opening AP split is drifting.
      final s = _species('even');
      final lvl = levelToWinHalf(s, s, baseLevel: 10, runs: 40);
      expect(lvl, isNotNull);
      expect(lvl!, inInclusiveRange(10, 13));
    });

    test('a weaker species needs a higher level, and the answer is stable', () {
      final weak = _species('weak2', hp: 45, atk: 34, def: 30, spd: 26);
      final strong = _species('strong2', hp: 70, atk: 55, def: 48, spd: 42);
      final lvl = levelToWinHalf(weak, strong, baseLevel: 10, runs: 40);
      expect(lvl, isNotNull);
      expect(lvl!, greaterThan(10));
      expect(lvl, lessThanOrEqualTo(kCreatureMaxLevel));
      expect(
        levelToWinHalf(weak, strong, baseLevel: 10, runs: 40),
        lvl,
        reason: 'seeded — same question, same answer',
      );
    });
  });

  group('proposeTuning', () {
    test('a dead ability gets cheaper', () {
      kAbilityDefs['dead'] = const AbilityDef(
        id: 'dead',
        name: 'Dead',
        element: CreatureElement.fire,
        kind: AbilityKind.damage,
        target: AbilityTarget.enemy,
        power: 30,
        apCost: 4,
      );
      final s = SpeciesDef(
        id: 'owner',
        name: 'owner',
        element: CreatureElement.fire,
        rarity: CreatureRarity.common,
        stats: _species('x').stats,
        stages: _species('x').stages,
        abilities: const [SpeciesAbility(abilityId: 'dead')],
      );
      kSpeciesDefs[s.id] = s;
      final changes = proposeTuning(
        results: [
          const PairingResult(
            aId: 'owner',
            bId: 'owner',
            runs: 100,
            aWinRate: 0.5,
            minActions: 5,
            maxActions: 8,
            medianActions: 6,
            tooShort: 0,
            tooLong: 0,
            aAbilityUses: {},
            bAbilityUses: {},
          ),
        ],
        species: kSpeciesDefs,
        abilities: kAbilityDefs,
      );
      final dead = changes.where((c) => c.id == 'dead').toList();
      expect(dead, hasLength(1));
      expect(dead.single.field, 'apCost');
      expect(dead.single.newValue, '3');
    });

    test('too-short fights shift attack into HP, budget preserved', () {
      final s = _species('rush');
      kSpeciesDefs[s.id] = s;
      final changes = proposeTuning(
        results: [
          const PairingResult(
            aId: 'rush',
            bId: 'rush',
            runs: 100,
            aWinRate: 0.5,
            minActions: 2,
            maxActions: 6,
            medianActions: 3,
            tooShort: 30,
            tooLong: 0,
            aAbilityUses: {},
            bAbilityUses: {},
          ),
        ],
        species: kSpeciesDefs,
        abilities: kAbilityDefs,
      );
      final statChange = changes.where((c) => c.kind == 'species').single;
      final updated = statChange.species!;
      final oldTotal = [
        for (final stat in kCombatStats) s.statCurve(stat).baseAt(0),
      ].reduce((a, b) => a + b);
      final newTotal = [
        for (final stat in kCombatStats) updated.statCurve(stat).baseAt(0),
      ].reduce((a, b) => a + b);
      expect(newTotal, closeTo(oldTotal, 0.001),
          reason: 'redistribution must not change the stat budget');
      expect(
        updated.statCurve(CreatureStat.hp).baseAt(0),
        greaterThan(s.statCurve(CreatureStat.hp).baseAt(0)),
      );
      expect(
        updated.statCurve(CreatureStat.attack).baseAt(0),
        lessThan(s.statCurve(CreatureStat.attack).baseAt(0)),
      );
    });
  });
}
