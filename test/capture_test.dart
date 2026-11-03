import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/area.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/expedition.dart';
import 'package:boddygame/features/creatures/models/species_def.dart';
import 'package:boddygame/features/creatures/services/capture_math.dart';
import 'package:boddygame/features/settlement/services/gold_economy.dart';

SpeciesDef _species(
  String id,
  CreatureRarity rarity, {
  double catchRate = 1.0,
}) => SpeciesDef(
  id: id,
  name: id,
  element: CreatureElement.fire,
  rarity: rarity,
  catchRate: catchRate,
  stats: const {},
  stages: const [
    SpeciesStage(name: 's'),
    SpeciesStage(name: 's'),
    SpeciesStage(name: 's'),
  ],
);

void main() {
  setUp(() {
    kSpeciesDefs
      ..clear()
      ..addAll({
        'mouse': _species('mouse', CreatureRarity.common),
        'wolf': _species('wolf', CreatureRarity.rare),
      });
  });

  // catchableSpecies reads the AREA defs (for the defeated legendaries), so a
  // test that rewrites them has to hand the real content back.
  final realAreas = Map.of(kAreaDefs);
  tearDown(() {
    kSpeciesDefs.clear();
    kAreaDefs
      ..clear()
      ..addAll(realAreas);
  });

  group('rarityWeights', () {
    test('sums to 100 by default', () {
      final w = rarityWeights();
      final sum = w.values.reduce((a, b) => a + b);
      expect(sum, closeTo(100, 1e-9));
    });
  });

  // ── What lives in the wild (user 2026-07-27) ─────────────────────────
  // "Nimm die Barriere raus, dass Monster nur bei gewissen Stufen des Pfades
  // gefangen werden können. Es sind alle immer frei zum Fangen, ausser die
  // Legendären, welche dem Pool erst nach dem Besiegen hinzugefügt werden."
  //
  // A hunt used to roll from the AREA's own pool — not any more, the pool is
  // global (catchableSpecies).
  group('catchableSpecies', () {
    test('every non-legendary species, whatever the path says', () {
      kSpeciesDefs['leg'] = _species('leg', CreatureRarity.legendary);
      final atStart = catchableSpecies(0).map((s) => s.id).toSet();
      expect(atStart, containsAll(['mouse', 'wolf']));
      expect(atStart.contains('leg'), isFalse, reason: 'undefeated legendary');
    });

    test('a legendary joins the pool once its region is cleared', () {
      kSpeciesDefs['leg'] = _species('leg', CreatureRarity.legendary);
      kAreaDefs
        ..clear()
        ..['a'] = const AreaDef(
          id: 'a',
          name: 'A',
          emoji: '🌲',
          order: 1,
          battleStage: 3,
          bossSpeciesId: 'leg',
        );
      // Standing ON the stage is not yet past it — the boss is still up.
      expect(defeatedLegendaryIds(3), isEmpty);
      expect(catchableSpecies(3).map((s) => s.id).contains('leg'), isFalse);
      // One further along the path and it is down.
      expect(defeatedLegendaryIds(4), {'leg'});
      expect(catchableSpecies(4).map((s) => s.id).contains('leg'), isTrue);
    });

    test('a species outside every area pool is still catchable', () {
      // The exact barrier that was removed: this one belongs to no region's
      // guest list at all, and used to be unreachable for that reason.
      kSpeciesDefs['stray'] = _species('stray', CreatureRarity.uncommon);
      kAreaDefs
        ..clear()
        ..['a'] = const AreaDef(
          id: 'a',
          name: 'A',
          emoji: '🌲',
          order: 1,
          battleStage: 1,
          speciesPoolIds: ['mouse'],
        );
      expect(catchableSpecies(0).map((s) => s.id), contains('stray'));
    });
  });

  group('rollEncounter', () {
    test('null when no species are defined at all', () {
      kSpeciesDefs.clear();
      expect(rollEncounter(math.Random(1), dungeonMaxStage: 0), isNull);
    });

    test('an undefeated legendary never turns up, a defeated one does', () {
      kSpeciesDefs['leg'] = _species('leg', CreatureRarity.legendary);
      kAreaDefs
        ..clear()
        ..['a'] = const AreaDef(
          id: 'a',
          name: 'A',
          emoji: '🌲',
          order: 1,
          battleStage: 1,
          bossSpeciesId: 'leg',
        );
      final rng = math.Random(9);
      for (var i = 0; i < 500; i++) {
        expect(
          rollEncounter(rng, dungeonMaxStage: 1)?.id,
          isNot('leg'),
        );
      }
      var seen = false;
      for (var i = 0; i < 500 && !seen; i++) {
        seen = rollEncounter(rng, dungeonMaxStage: 2)?.id == 'leg';
      }
      expect(seen, isTrue, reason: 'a beaten legendary must appear');
    });

  });

  group('catch QTE', () {
    test('ring speed is fixed per rarity — catchRate does not slow it', () {
      // catchRate no longer feeds ring speed (user design 2026-07-17); rarer
      // species just shrink faster.
      final common = _species('c', CreatureRarity.common);
      final legendary = _species('l', CreatureRarity.legendary);
      expect(qteSeconds(legendary), lessThan(qteSeconds(common)));
    });

    test('later rounds shrink faster; slippery species are faster', () {
      final rare = _species('r', CreatureRarity.rare);
      expect(qteSeconds(rare, round: 1), lessThan(qteSeconds(rare)));
      final slippery = _species('s', CreatureRarity.rare, catchRate: 0.7);
      expect(qteSeconds(slippery), lessThan(qteSeconds(rare)));
    });

    test('a higher active catchRate widens the golden zone', () {
      // catchRate's ONLY effect now: a dedicated catcher makes the band wider.
      double width(int cr) {
        final w = qteWindow(CreatureRarity.rare, catchRate: cr);
        return w.hi - w.lo;
      }
      expect(width(150), greaterThan(width(0)));
      expect(width(0), closeTo(width(0), 1e-9)); // 0 = the base width
      // The band stays centred whatever the catchRate.
      final w = qteWindow(CreatureRarity.rare, catchRate: 200);
      expect((w.lo + w.hi) / 2, closeTo(kQteWindowCenter, 1e-9));
    });

    test('rarer finds need more perfect hits', () {
      expect(qteHitsRequired(CreatureRarity.common), 1);
      expect(qteHitsRequired(CreatureRarity.rare), 2);
      expect(qteHitsRequired(CreatureRarity.legendary), 4);
      expect(
        qteHitsRequired(CreatureRarity.legendary),
        greaterThan(qteHitsRequired(CreatureRarity.epic) - 1),
      );
    });

    test('rarer finds must be fought lower before the catch opens', () {
      expect(catchHpThreshold(CreatureRarity.common), 0.70);
      expect(catchHpThreshold(CreatureRarity.legendary), 0.12);
      double prev = 1.0;
      for (final r in CreatureRarity.values) {
        final t = catchHpThreshold(r);
        expect(t, lessThan(prev), reason: '${r.name} threshold must drop');
        prev = t;
      }
    });

    test('the tap window narrows with rarity', () {
      final common = qteWindow(CreatureRarity.common);
      final legendary = qteWindow(CreatureRarity.legendary);
      expect(common.hi - common.lo, greaterThan(legendary.hi - legendary.lo));
      // Both bands sit around the shared center.
      expect((common.lo + common.hi) / 2, closeTo(kQteWindowCenter, 1e-9));
      expect((legendary.lo + legendary.hi) / 2, closeTo(kQteWindowCenter, 1e-9));
    });

    test('fighting deeper below the threshold widens the window', () {
      // User's example: catchable from 50%, monster at 25% total HP → halfway
      // into the band → zone +50%.
      const r = CreatureRarity.uncommon; // threshold 0.55
      final threshold = catchHpThreshold(r);
      expect(catchDepth(r, threshold), 0); // at the threshold: no bonus
      expect(catchDepth(r, threshold / 2), closeTo(0.5, 1e-9));
      expect(catchDepth(r, 0), 1); // approaching 0 HP: full bonus
      expect(catchDepth(r, 0.9), 0); // above threshold clamps to 0

      double width(double hp) {
        final w = qteWindow(r, hpFraction: hp);
        return w.hi - w.lo;
      }

      final base = width(threshold);
      expect(width(threshold / 2), closeTo(base * 1.5, 1e-9)); // +50%
      expect(width(0), closeTo(base * 2.0, 1e-9)); // doubled
      // Default (no hpFraction) = base width, so old call sites stay valid.
      final def = qteWindow(r);
      expect(def.hi - def.lo, closeTo(base, 1e-9));
    });

  });

  group('hunt variants (5 fixed step counts, user 2026-10-02)', () {
    test('effective steps scale with timeScale and travelMult, never free',
        () {
      final o = kCaptureHuntOptions.first;
      expect(effectiveHuntSteps(o), o.steps);
      expect(effectiveHuntSteps(o, timeScale: 0.5), (o.steps * 0.5).round());
      expect(
        effectiveHuntSteps(o, travelMult: 2.0),
        (o.steps / 2.0).round(),
      );
      // Even scaled far down (the tutorial's jumpstart), at least 1 step.
      expect(effectiveHuntSteps(o, timeScale: 0.001), greaterThanOrEqualTo(1));
    });

    test('longer variants: more steps, more finds', () {
      var prevSteps = 0;
      var prevFinds = 0;
      for (final o in kCaptureHuntOptions) {
        expect(o.steps, greaterThan(prevSteps),
            reason: 'step target strictly increases');
        expect(o.finds, greaterThan(prevFinds),
            reason: 'finds strictly increase');
        prevSteps = o.steps;
        prevFinds = o.finds;
      }
    });

    // 'every hunt sends exactly ONE monster' (added 2026-07-30, removed
    // 2026-09-11): CaptureHuntOption no longer carries a hunters field at
    // all. All of a hunt's finds are now fought as ONE continuous
    // multi-wild battle rather than one battle per find, and team size
    // follows the same growing teamSizeCap Gather already uses — see
    // kCaptureHuntOptions's own comment.

    test('the five variants match the user spec (500..10000, finds 1..8)', () {
      expect(kCaptureHuntOptions.map((o) => o.steps),
          [500, 1000, 2000, 5000, 10000]);
      expect(kCaptureHuntOptions.map((o) => o.finds), [1, 2, 3, 5, 8]);
    });

    test('a longer hunt never pays MORE per step than the shortest', () {
      // 10,000 steps returns 8 finds where 20× 500-step hunts would return
      // 20. If that ever inverts, the whole ladder collapses onto its last
      // rung. Non-strict (≤): the first two rungs tie at exactly the same
      // finds/step rate, which is fine — "never better", not "always worse".
      final shortRate =
          kCaptureHuntOptions.first.finds / kCaptureHuntOptions.first.steps;
      for (final o in kCaptureHuntOptions.skip(1)) {
        final rate = o.finds / o.steps;
        expect(rate, lessThanOrEqualTo(shortRate),
            reason: '${o.id} pays better per step than the shortest hunt');
      }
    });

  });

  group('capture payload helpers', () {
    Expedition exp(Map<String, dynamic> payload) => Expedition(
      id: 'e',
      userId: 'u',
      type: ExpeditionType.capture,
      areaId: 'a',
      startedAt: DateTime(2026),
      payload: payload,
    );

    test('multi-find payload round-trips finds and progress', () {
      final e = exp({'speciesIds': ['mouse', 'wolf'], 'level': 5, 'done': 1});
      expect(e.captureFindSpeciesIds, ['mouse', 'wolf']);
      expect(e.captureFindsDone, 1);
    });

    test('legacy single-find payload reads as one find', () {
      final e = exp({'speciesId': 'mouse', 'level': 5});
      expect(e.captureFindSpeciesIds, ['mouse']);
      expect(e.captureFindsDone, 0);
    });
  });

  group('Balkenjagd (bar-chase catch, user 2026-10-01)', () {
    test('rarity speed/duration both strictly increase', () {
      var prevSpeed = 0.0;
      var prevDuration = 0;
      for (final r in CreatureRarity.values) {
        expect(barBaseSpeed(r), greaterThan(prevSpeed));
        expect(barDurationMs(r), greaterThan(prevDuration));
        prevSpeed = barBaseSpeed(r);
        prevDuration = barDurationMs(r);
      }
    });

    test('a longer duration never outpaces the speed increase (net harder)',
        () {
      // "mehr Zeit, aber auch mehr Zeit für Fehler" — speed growth must beat
      // duration growth, or a rarer find would actually be EASIER overall.
      var prevRatio = double.infinity;
      for (final r in CreatureRarity.values) {
        final ratio = barBaseSpeed(r) * barDurationMs(r);
        expect(ratio, greaterThan(prevRatio == double.infinity ? 0 : prevRatio));
        prevRatio = ratio;
      }
    });

    test('Resteleben depth slows the wild, floor at 0.55×', () {
      const r = CreatureRarity.rare;
      final atThreshold = barSpeedMul(r, catchHpThreshold(r));
      final nearZero = barSpeedMul(r, 0.0);
      expect(atThreshold, closeTo(1.0, 1e-9)); // depth 0 = no slowdown yet
      expect(nearZero, closeTo(0.55, 1e-9)); // depth 1 = full slowdown
      expect(nearZero, lessThan(atThreshold));
    });

    test('catchRate widens the bar with diminishing returns, never unbounded',
        () {
      final none = barWidthFraction(0);
      final some = barWidthFraction(18);
      final lots = barWidthFraction(1000);
      expect(none, closeTo(kBarWidthBase, 1e-9));
      expect(some, greaterThan(none));
      expect(lots, greaterThan(some));
      expect(lots, lessThan(kBarWidthBase + kBarWidthMaxBonus));
    });

    test('skill points earned over a FULL round always sum to kBarSkillMax',
        () {
      for (final ms in kBarDurationMs.values) {
        final total = barSkillGainPerSecond(ms) * (ms / 1000);
        expect(total, closeTo(kBarSkillMax, 1e-9));
      }
    });

    test('percent is item-start + skill, clamped, and the floor never drops',
        () {
      expect(barCatchPercent(0.40, 0), closeTo(40, 1e-9));
      expect(barCatchPercent(0.40, kBarSkillMax), closeTo(100, 1e-9));
      expect(barCatchPercent(0.10, kBarSkillMax), closeTo(70, 1e-9));
      // Over-accumulating skill (shouldn't happen, but the clamp must hold).
      expect(barCatchPercent(0.40, 999), closeTo(100, 1e-9));
    });

    test('only the top item can reach a true 100% ceiling', () {
      // Every tier's ceiling is itemStart*100 + kBarSkillMax; only 40% + 60
      // hits 100 exactly. Cheaper tiers cap below it even on a flawless run.
      expect(barCatchPercent(0.40, kBarSkillMax), 100);
      expect(barCatchPercent(0.25, kBarSkillMax), lessThan(100));
      expect(barCatchPercent(0.10, kBarSkillMax), lessThan(100));
    });
  });

  group('Expedition step-gating (capture only, user 2026-10-02)', () {
    Expedition capture({int stepsTarget = 1000, int stepsWalked = 0}) =>
        Expedition(
          id: 'e',
          userId: 'u',
          type: ExpeditionType.capture,
          areaId: 'a',
          startedAt: DateTime(2026),
          payload: {'stepsTarget': stepsTarget, 'stepsWalked': stepsWalked},
        );

    Expedition gather() => Expedition(
      id: 'g',
      userId: 'u',
      type: ExpeditionType.gather,
      areaId: 'a',
      startedAt: DateTime(2026),
      duration: const Duration(hours: 1),
    );

    test('only capture is step-gated — gather keeps the wall clock', () {
      expect(capture().isStepGated, isTrue);
      expect(gather().isStepGated, isFalse);
    });

    test('progress/isFinished read steps, never the clock', () {
      final e = capture(stepsTarget: 1000, stepsWalked: 400);
      // A wildly wrong "now" changes nothing — steps drive this, not time.
      expect(e.progress(DateTime(2099)), closeTo(0.4, 1e-9));
      expect(e.isFinished(DateTime(2026)), isFalse);
      expect(e.remaining(DateTime.now()), Duration.zero);
    });

    test('isFinished flips exactly when stepsWalked reaches the target', () {
      final now = DateTime.now();
      expect(
        capture(stepsTarget: 500, stepsWalked: 499).isFinished(now),
        isFalse,
      );
      expect(
        capture(stepsTarget: 500, stepsWalked: 500).isFinished(now),
        isTrue,
      );
    });

    test('stepsRemaining never goes negative', () {
      expect(capture(stepsTarget: 500, stepsWalked: 900).stepsRemaining, 0);
    });
  });

  group('goldToSkipSteps', () {
    test('free once there is nothing left', () {
      expect(goldToSkipSteps(0), 0);
    });

    test('scales with remaining steps, never free otherwise', () {
      expect(goldToSkipSteps(10), greaterThanOrEqualTo(1));
      expect(goldToSkipSteps(10000), greaterThan(goldToSkipSteps(10)));
    });
  });
}
