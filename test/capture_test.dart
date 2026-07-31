import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/area.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/expedition.dart';
import 'package:boddygame/features/creatures/models/species_def.dart';
import 'package:boddygame/features/creatures/services/capture_math.dart';

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

AreaDef _area(int danger, {List<String> pool = const []}) => AreaDef(
  id: 'a$danger',
  name: 'A',
  emoji: '🌲',
  order: 1,
  battleStage: 1,
  dangerLevel: danger,
  speciesPoolIds: pool,
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
    test('sum to 100 at every danger and shift toward rare', () {
      for (var d = 1; d <= 5; d++) {
        final w = rarityWeights(d);
        final sum = w.values.reduce((a, b) => a + b);
        expect(sum, closeTo(100, 1e-9), reason: 'danger $d');
      }
      final safe = rarityWeights(1);
      final wild = rarityWeights(5);
      expect(wild[CreatureRarity.common]!, lessThan(safe[CreatureRarity.common]!));
      expect(wild[CreatureRarity.rare]!, greaterThan(safe[CreatureRarity.rare]!));
      expect(wild[CreatureRarity.legendary]!,
          greaterThan(safe[CreatureRarity.legendary]!));
    });
  });

  // ── What lives in the wild (user 2026-07-27) ─────────────────────────
  // "Nimm die Barriere raus, dass Monster nur bei gewissen Stufen des Pfades
  // gefangen werden können. Es sind alle immer frei zum Fangen, ausser die
  // Legendären, welche dem Pool erst nach dem Besiegen hinzugefügt werden."
  //
  // A hunt used to roll from the AREA's own pool, and areas open with the path,
  // so the roster you could reach was a function of progress. The area now
  // supplies only the DANGER the rarity odds are read from.
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
          dangerLevel: 5,
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
          dangerLevel: 1,
          speciesPoolIds: ['mouse'],
        );
      expect(catchableSpecies(0).map((s) => s.id), contains('stray'));
    });
  });

  group('rollEncounter', () {
    test('null when no species are defined at all', () {
      kSpeciesDefs.clear();
      expect(rollEncounter(_area(1), math.Random(1), dungeonMaxStage: 0),
          isNull);
    });

    test('rolls species the area never listed', () {
      // The area's pool names only the mouse; the wolf must still turn up.
      final rng = math.Random(5);
      var sawWolf = false;
      for (var i = 0; i < 500 && !sawWolf; i++) {
        sawWolf = rollEncounter(
              _area(5, pool: ['mouse']),
              rng,
              dungeonMaxStage: 0,
            )?.id ==
            'wolf';
      }
      expect(sawWolf, isTrue);
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
          dangerLevel: 5, // legendary weight is highest here
          bossSpeciesId: 'leg',
        );
      final rng = math.Random(9);
      for (var i = 0; i < 500; i++) {
        expect(
          rollEncounter(_area(5), rng, dungeonMaxStage: 1)?.id,
          isNot('leg'),
        );
      }
      var seen = false;
      for (var i = 0; i < 500 && !seen; i++) {
        seen = rollEncounter(_area(5), rng, dungeonMaxStage: 2)?.id == 'leg';
      }
      expect(seen, isTrue, reason: 'a beaten legendary must appear');
    });

    test('dangerous areas find the rare species more often', () {
      int rareCount(int danger) {
        final rng = math.Random(42);
        var count = 0;
        for (var i = 0; i < 2000; i++) {
          if (rollEncounter(_area(danger), rng, dungeonMaxStage: 0)?.id ==
              'wolf') {
            count++;
          }
        }
        return count;
      }

      final safe = rareCount(1);
      final wild = rareCount(5);
      expect(safe, greaterThan(0)); // rare is possible even in the safe area
      expect(wild, greaterThan(safe * 2)); // 10% → 30% of the weight (~3x)
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

  group('hunt variants (6 fixed durations)', () {
    test('fixed duration per variant, scaled only by timeScale', () {
      final o = kCaptureHuntOptions.first;
      expect(captureDuration(o).inSeconds, o.seconds);
      expect(
        captureDuration(o, timeScale: 0.5).inSeconds,
        (o.seconds * 0.5).round(),
      );
    });

    test('longer variants: longer, more finds, rarer odds', () {
      var prevSeconds = 0;
      var prevFinds = 0;
      var prevBias = -1.0;
      for (final o in kCaptureHuntOptions) {
        expect(o.seconds, greaterThan(prevSeconds),
            reason: 'duration strictly increases');
        expect(o.finds, greaterThan(prevFinds),
            reason: 'finds strictly increase');
        expect(o.rareBias, greaterThanOrEqualTo(prevBias),
            reason: 'rare bias never drops');
        prevSeconds = o.seconds;
        prevFinds = o.finds;
        prevBias = o.rareBias;
      }
    });

    test('every hunt sends exactly ONE monster', () {
      // User 2026-07-30: "Pro Hunt wird immer nur ein Monster geschickt."
      // Party size used to climb with the trip length, which made the long
      // hunts unreachable for the players who most needed them and tied up six
      // monsters for a day. Time is the only price now.
      for (final o in kCaptureHuntOptions) {
        expect(o.hunters, 1, reason: o.id);
      }
    });

    test('the six variants match the user spec (10m..24h, finds 1..12)', () {
      expect(kCaptureHuntOptions.map((o) => o.seconds),
          [600, 1800, 3600, 14400, 28800, 86400]);
      // The user's ladder: 60' = 3, 4 h = 5, 8 h = 8, 24 h = 12.
      expect(kCaptureHuntOptions.map((o) => o.finds), [1, 2, 3, 5, 8, 12]);
    });

    test('a longer hunt is a convenience, never the efficient play', () {
      // 24 h returns 12 finds where 24 ten-minute hunts would return 24. If
      // that ever inverts, the whole ladder collapses onto its last rung.
      final short = kCaptureHuntOptions.first;
      for (final o in kCaptureHuntOptions.skip(1)) {
        final findsPerSecond = o.finds / o.seconds;
        expect(findsPerSecond, lessThan(short.finds / short.seconds),
            reason: '${o.id} pays better per minute than the shortest hunt');
      }
    });

    test('rare bias shifts odds toward the rare end', () {
      final base = rarityWeights(1);
      final biased = biasedRarityWeights(1, 1.0);
      // Common share falls, legendary share rises.
      expect(biased[CreatureRarity.common]!,
          lessThan(base[CreatureRarity.common]!));
      expect(biased[CreatureRarity.legendary]!,
          greaterThan(base[CreatureRarity.legendary]!));
      // Zero bias is a no-op.
      expect(biasedRarityWeights(1, 0), base);
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
}
