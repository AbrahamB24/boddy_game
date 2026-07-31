import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/species_balance.dart';

// The breeding CLOCK (user 2026-07-26). Two things are pinned here:
//
//  1. mating and hatching are separate, authorable durations. They used to be
//     one number, so tuning the egg meant retuning the mating.
//  2. the time↔power pair is a true inverse. The Species-Budget screen asks
//     "which power reaches this duration" and the building preview answers
//     "which duration does this power reach" — if those two ever disagree, the
//     Dev-Mode numbers become fiction.
void main() {
  tearDown(() => kSpeciesBalance = defaultSpeciesBalance());

  group('the diminishing-returns curve (no ceiling since 2026-07-26)', () {
    test('an empty post costs nothing and changes nothing', () {
      expect(breedingTimeCut(0), 0);
      expect(breedingHours(8, 0), 8);
    });

    test('power K halves the duration — that is what K now means', () {
      expect(breedingTimeCut(kBreedingK), closeTo(0.5, 1e-9));
      expect(breedingHours(8, kBreedingK), closeTo(4, 1e-9));
    });

    test('past K it keeps improving instead of stopping at −50 %', () {
      // The removed cap: −50 % used to be the end of the road, so a levelled
      // Breeding Hut bought fractions of a percent.
      expect(breedingTimeCut(kBreedingK * 4), closeTo(0.8, 1e-9));
      expect(breedingTimeCut(kBreedingK * 9), closeTo(0.9, 1e-9));
      expect(breedingHours(8, kBreedingK * 9), closeTo(0.8, 1e-9));
    });

    test('returns still diminish — each further point buys less', () {
      final first = breedingTimeCut(60) - breedingTimeCut(0);
      final second = breedingTimeCut(120) - breedingTimeCut(60);
      expect(second, lessThan(first));
    });

    test('a duration approaches zero but never reaches it', () {
      expect(breedingHours(8, 1e9), greaterThan(0));
      expect(breedingHours(8, 1e9), lessThan(0.001));
      expect(breedingTimeCut(1e9), lessThan(1.0));
    });
  });

  group('breedingPowerForHours (the Dev-Mode question)', () {
    test('round-trips against breedingHours', () {
      for (final base in [4.0, 8.0, 16.0]) {
        // Ratios, not absolute hours — including well past the old −50 % wall.
        for (final frac in [0.95, 0.8, 0.5, 0.2, 0.05]) {
          final target = base * frac;
          final p = breedingPowerForHours(base, target);
          expect(p, isNotNull, reason: '$base → $target should be reachable');
          expect(breedingHours(base, p!), closeTo(target, 1e-9));
        }
      }
    });

    test('a target at or above the base needs no staff at all', () {
      expect(breedingPowerForHours(8, 8), 0);
      expect(breedingPowerForHours(8, 12), 0);
    });

    test('halving the base costs exactly K — the old hard ceiling', () {
      expect(breedingPowerForHours(8, 4), closeTo(kBreedingK, 1e-9));
    });

    test('beyond that it answers with a price instead of "impossible"', () {
      // This is what the removed cap changed: −87.5 % used to be unreachable
      // at any stat; now it simply costs a lot.
      expect(breedingPowerForHours(8, 1), closeTo(kBreedingK * 7, 1e-9));
    });

    test('only a zero-or-negative duration has no answer', () {
      expect(breedingPowerForHours(8, 0), isNull);
      expect(breedingPowerForHours(8, -2), isNull);
    });

    test('the answer does not depend on the base — only the ratio does', () {
      // Halving any duration by 25% costs the same power. This is what lets the
      // Breeding tab print one "power → speed-up" ruler for every rarity.
      expect(
        breedingPowerForHours(4, 3),
        closeTo(breedingPowerForHours(16, 12)!, 1e-9),
      );
    });

    test('an unusable base is refused rather than returning nonsense', () {
      expect(breedingPowerForHours(0, 1), isNull);
    });
  });

  group('hatching has its own duration', () {
    test('the default seeds it equal to the mating time', () {
      // The VALUE moved on 2026-07-29 (the author's ladder, 16/32/64/128);
      // what matters here is that the two clocks still start out equal, so
      // a Hatchery with no separate tuning behaves as it always did.
      final rare = defaultSpeciesBalance().of(CreatureRarity.rare);
      expect(rare.breedHours, 64);
      expect(rare.hatchHours, rare.breedHours);
    });

    test('the two are tuned independently and survive a round-trip', () {
      final cfg = SpeciesBalance(
        byRarity: {
          for (final r in CreatureRarity.values)
            r: defaultSpeciesBalance()
                .of(r)
                .copyWith(breedHours: 5, hatchHours: 20),
        },
      );
      final back = SpeciesBalance.fromJson(cfg.toJson());
      expect(back.of(CreatureRarity.rare).breedHours, 5);
      expect(back.of(CreatureRarity.rare).hatchHours, 20);
    });

    test('a config saved before the split keeps hatching at ITS breed time', () {
      // The pre-2026-07-26 rows have no hatchHours; the Hatchery ran on
      // breedHours back then, so that — not the code default — is the honest
      // fallback.
      final legacy = {
        for (final r in CreatureRarity.values)
          r.name: {
            'combatBase': 100.0,
            'workBase': 100.0,
            'combatGrowth': 3.0,
            'workGrowth': 3.0,
            'catchRate': 1.0,
            'breedHours': 30.0,
          },
      };
      final back = SpeciesBalance.fromJson(legacy);
      expect(back.of(CreatureRarity.rare).breedHours, 30);
      expect(back.of(CreatureRarity.rare).hatchHours, 30);
    });
  });
}
