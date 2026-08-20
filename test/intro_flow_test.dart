import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/area.dart';
import 'package:boddygame/features/creatures/models/combatant.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/models/species_def.dart';
import 'package:boddygame/features/creatures/services/capture_math.dart';
import 'package:boddygame/features/creatures/services/gather_math.dart';
import 'package:boddygame/features/onboarding/intro_flow.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart';

const _area = AreaDef(
  id: 'a',
  name: 'A',
  emoji: '🌲',
  order: 1,
  battleStage: 1,
  dangerLevel: 2,
);

const _spot = ResourceSpotDef(
  id: 'sp',
  resource: 'wood',
);

CreatureInstance _mob() => CreatureInstance(
  id: 'c',
  userId: 'u',
  speciesId: 's',
  gender: CreatureGender.male,
  statBase: const {
    CreatureStat.gathering: 25.0,
    CreatureStat.carry: 40.0,
  },
  statSlope: const {},
);

SpeciesDef _species() => SpeciesDef(
  id: 'mouse',
  name: 'Mouse',
  element: CreatureElement.fire,
  rarity: CreatureRarity.common,
  stats: const {
    CreatureStat.hp: StatCurve(stageBase: [60, 60, 60], growth: 1.5),
    CreatureStat.attack: StatCurve(stageBase: [40, 40, 40], growth: 1),
    CreatureStat.defense: StatCurve(stageBase: [40, 40, 40], growth: 1),
  },
  stages: const [
    SpeciesStage(name: 's'),
    SpeciesStage(name: 's'),
    SpeciesStage(name: 's'),
  ],
);

SpeciesDef _rarity(
  String id,
  CreatureRarity rarity, {
  CreatureElement element = CreatureElement.fire,
}) => SpeciesDef(
  id: id,
  name: id,
  element: element,
  rarity: rarity,
  stats: const {},
  stages: const [
    SpeciesStage(name: 's'),
    SpeciesStage(name: 's'),
    SpeciesStage(name: 's'),
  ],
);

void main() {
  group('starter pool', () {
    tearDown(kSpeciesDefs.clear);

    test('offers the fire/water/plant epics and nothing else', () {
      kSpeciesDefs
        ..clear()
        ..addAll({
          'fire': _rarity('fire', CreatureRarity.epic,
              element: CreatureElement.fire),
          'water': _rarity('water', CreatureRarity.epic,
              element: CreatureElement.water),
          'plant': _rarity('plant', CreatureRarity.epic,
              element: CreatureElement.plant),
          // Not starters: an epic of the wrong element, and the right element
          // at the wrong rarity.
          'shadow': _rarity('shadow', CreatureRarity.epic,
              element: CreatureElement.shadow),
          'commonFire': _rarity('commonFire', CreatureRarity.common,
              element: CreatureElement.fire),
        });
      final choices = starterChoices();
      expect(choices, hasLength(3));
      expect(choices.every((s) => s.rarity == CreatureRarity.epic), isTrue);
      expect(
        choices.map((s) => s.element).toSet(),
        {CreatureElement.fire, CreatureElement.water, CreatureElement.plant},
      );
    });

    test('is empty when content exists but no starter epic does', () {
      // Not the same as "no species defined" — the picker says so, because
      // otherwise a dev sees "none defined" while staring at their species.
      kSpeciesDefs
        ..clear()
        ..addAll({'leg': _rarity('leg', CreatureRarity.legendary)});
      expect(kSpeciesDefs, isNotEmpty);
      expect(starterChoices(), isEmpty);
    });

    test('is sorted by name so the grid order is stable', () {
      kSpeciesDefs
        ..clear()
        ..addAll({
          'c': _rarity('c', CreatureRarity.epic,
              element: CreatureElement.fire),
          'a': _rarity('a', CreatureRarity.epic,
              element: CreatureElement.water),
          'b': _rarity('b', CreatureRarity.epic,
              element: CreatureElement.plant),
        });
      expect(starterChoices().map((s) => s.name), ['a', 'b', 'c']);
    });
  });

  group('IntroStep', () {
    test('walks the chain in order and terminates at done', () {
      var step = IntroStep.pickStarter;
      final seen = <IntroStep>[step];
      while (step != IntroStep.done) {
        step = step.next;
        seen.add(step);
      }
      expect(seen, IntroStep.values);
      // done is absorbing — a late milestone callback can't wrap around.
      expect(IntroStep.done.next, IntroStep.done);
    });

    test('the script order encodes its causal chain', () {
      // Each bound is a real dependency of the guided script, not taste:
      int at(IntroStep s) => s.index;
      // Nothing works without a creature.
      expect(at(IntroStep.pickStarter), 0);
      // The first node fight is what leaves the starter hurt.
      expect(
        at(IntroStep.firstNode),
        lessThan(at(IntroStep.buildHealingHut)),
      );
      // The hut must stand before a healer can be stationed there.
      expect(
        at(IntroStep.buildHealingHut),
        lessThan(at(IntroStep.assignHealer)),
      );
      // ...and before it can treat anyone.
      expect(
        at(IntroStep.assignHealer),
        lessThan(at(IntroStep.healStarter)),
      );
      // A hurt starter can't hunt — heal first, catch second.
      expect(at(IntroStep.healStarter), lessThan(at(IntroStep.firstCapture)));
      // Two monsters before the second node is asked of them.
      expect(at(IntroStep.firstCapture), lessThan(at(IntroStep.secondNode)));
    });

    test('every build step points at a real bundled building', () {
      for (final entry in kIntroBuildSteps.entries) {
        expect(
          kFallbackBuildingDefs.containsKey(entry.key),
          isTrue,
          reason: '${entry.key} is not a bundled building',
        );
        expect(introBuildTarget(entry.value), entry.key);
      }
      // Steps that aren't build steps have no target.
      expect(introBuildTarget(IntroStep.pickStarter), isNull);
      expect(introBuildTarget(IntroStep.done), isNull);
    });

    test('only done is inactive — the jumpstart window is the chain', () {
      for (final s in IntroStep.values) {
        expect(s.isActive, s != IntroStep.done, reason: s.name);
      }
    });

    test('an out-of-range persisted value reads as done, never as step 0', () {
      // The failure that matters: a veteran whose column is missing/garbage
      // must NOT be dropped back into the tutorial with a fresh jumpstart.
      expect(IntroStep.fromIndex(-1), IntroStep.done);
      expect(IntroStep.fromIndex(99), IntroStep.done);
      expect(IntroStep.fromIndex(0), IntroStep.pickStarter);
      expect(
        IntroStep.fromIndex(IntroStep.done.index),
        IntroStep.done,
      );
    });
  });

  group('intro cards', () {
    test('every active step has copy, and done has none', () {
      for (final s in IntroStep.values) {
        final card = introCardFor(s);
        if (s == IntroStep.done) {
          expect(card, isNull);
          continue;
        }
        expect(card, isNotNull, reason: s.name);
        expect(card!.title.trim(), isNotEmpty, reason: s.name);
        expect(card.body.trim(), isNotEmpty, reason: s.name);
      }
    });

    test('a call-to-action always has somewhere to go', () {
      for (final s in IntroStep.values) {
        final card = introCardFor(s);
        if (card == null) continue;
        expect(
          card.ctaLabel == null,
          card.destination == null,
          reason: '${s.name}: label and destination must come as a pair',
        );
      }
    });
  });

  group('jumpstart', () {
    test('scales time only while active', () {
      expect(jumpstartTimeScale(true), kJumpstartTimeScale);
      expect(jumpstartTimeScale(false), 1.0);
    });

    test('is a speed-up, not a slow-down', () {
      expect(kJumpstartTimeScale, greaterThan(0));
      expect(kJumpstartTimeScale, lessThan(1));
      expect(kJumpstartEnemyStatMult, greaterThan(0));
      expect(kJumpstartEnemyStatMult, lessThan(1));
    });

    test('shortens a gather trip proportionally', () {
      GatherPlan plan({double timeScale = 1.0}) => planGather(
        area: _area,
        spot: _spot,
        members: [_mob()],
        availableStock: 600,
        timeScale: timeScale,
      );
      final full = plan().duration.inSeconds;
      final boosted = plan(timeScale: kJumpstartTimeScale).duration.inSeconds;
      expect(boosted, closeTo(full * kJumpstartTimeScale, 1));
    });

    test('shortens a capture hunt proportionally', () {
      final o = kCaptureHuntOptions.first;
      final full = captureDuration(o).inSeconds;
      final boosted =
          captureDuration(o, timeScale: kJumpstartTimeScale).inSeconds;
      expect(boosted, closeTo(full * kJumpstartTimeScale, 1));
    });

    test('weakens a wild without touching the genes a catch keeps', () {
      final species = _species();
      // Same seed both sides: only statScale differs, so any gene difference
      // would be the scale leaking where it must not.
      Combatant wild(double scale) => Combatant.fromSpecies(
        species,
        level: 5,
        id: 'w',
        rng: math.Random(42),
        statScale: scale,
      );
      final normal = wild(1.0);
      final eased = wild(kJumpstartEnemyStatMult);

      expect(eased.maxHp, lessThan(normal.maxHp));
      expect(
        eased.stats[CreatureStat.attack]!,
        lessThan(normal.stats[CreatureStat.attack]!),
      );
      // THE invariant: a monster caught during the intro is a full-quality
      // individual — the handicap is battle stats only.
      expect(eased.wildStatBase, normal.wildStatBase);
      expect(eased.wildStatSlope, normal.wildStatSlope);
    });

    test('a stat can never be scaled away to zero', () {
      final species = _species();
      final crushed = Combatant.fromSpecies(
        species,
        level: 1,
        id: 'w',
        rng: math.Random(1),
        statScale: 0.001,
      );
      for (final entry in crushed.stats.entries) {
        expect(entry.value, greaterThanOrEqualTo(1), reason: entry.key.name);
      }
      expect(crushed.maxHp, greaterThanOrEqualTo(1));
    });
  });

  // docs/balancing.md §6: Era I in 5–7 days and 5–8 catches/day are RATES.
  // The jumpstart must stay a temporary multiplier layered ON TOP of the
  // balanced values — the moment it becomes the default, both anchors move.
  group('the balanced path stays the default', () {
    test('gather and capture are unscaled unless a caller opts in', () {
      final unscaled = planGather(
        area: _area,
        spot: _spot,
        members: [_mob()],
        availableStock: 600,
      );
      final explicit = planGather(
        area: _area,
        spot: _spot,
        members: [_mob()],
        availableStock: 600,
        timeScale: 1.0,
      );
      expect(unscaled.duration, explicit.duration);
      final o = kCaptureHuntOptions.first;
      expect(captureDuration(o), captureDuration(o, timeScale: 1.0));
    });

    test('wild stats are unscaled unless a caller opts in', () {
      final species = _species();
      Combatant wild({double? scale}) => Combatant.fromSpecies(
        species,
        level: 5,
        id: 'w',
        rng: math.Random(7),
        statScale: scale ?? 1.0,
      );
      expect(wild().stats, wild(scale: 1.0).stats);
    });
  });
}
