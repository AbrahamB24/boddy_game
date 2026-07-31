import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/models/species_balance.dart';
import 'package:boddygame/features/creatures/models/species_def.dart';
import 'package:boddygame/features/creatures/services/breeding_cost.dart';

// BREEDING COSTS SUPPLIES (user 2026-07-27: "Breeding soll luxuswaren kosten
// von der ära, aus welcher die Monster stammen").
//
// It was the one creature sink that was entirely free — a hut with a spare slot
// had no reason ever to be idle. The bill follows the HEALING rule: the goods
// of the PARENTS' era, not the settlement's, paid from what you actually have.

SpeciesDef _species(
  String id, {
  CreatureRarity rarity = CreatureRarity.common,
  int tier = 1,
}) => SpeciesDef(
  id: id,
  name: id,
  element: CreatureElement.fire,
  rarity: rarity,
  tier: tier,
  stats: const {},
  stages: const [SpeciesStage(name: 's0')],
);

CreatureInstance _mob(String speciesId, CreatureGender gender) =>
    CreatureInstance(
      id: '$speciesId-${gender.name}',
      userId: 'u',
      speciesId: speciesId,
      gender: gender,
      statBase: const {},
      statSlope: const {},
    );

/// A pair of [speciesId], registered in the def table so `.species` resolves.
(CreatureInstance, CreatureInstance) _pair(SpeciesDef def) {
  kSpeciesDefs[def.id] = def;
  return (_mob(def.id, CreatureGender.male), _mob(def.id, CreatureGender.female));
}

void main() {
  setUp(() => kSpeciesBalance = defaultSpeciesBalance());

  group('what a mating costs', () {
    test('an era-I pair is billed in era-I supplies', () {
      final (m, f) = _pair(_species('starter'));
      final cost = breedCost(m, f, {'fish': 100, 'fur': 100});
      expect(cost.keys, everyElement(isIn(['fish', 'fur'])));
      expect(cost.values.fold<double>(0, (a, b) => a + b),
          kSpeciesBalance.of(CreatureRarity.common).breedGoods);
    });

    test('a region-3 pair demands region-3 supplies — not the settlement\'s',
        () {
      // The whole point of the era rule: what you pay is decided by where the
      // MONSTERS come from. A late-region pair reaches for wine and cheese even
      // in a settlement that has plenty of fish.
      final (m, f) = _pair(_species('deepwood', tier: 3));
      const wineOnly = {'wine': 999.0};
      expect(breedCost(m, f, wineOnly)['wine'], isNotNull,
          reason: 'era-3 goods are on the table for a tier-3 species');

      // The same cellar buys a starter pair nothing: wine is not era-I supply,
      // so the bill falls back to demanding fish it does not have.
      final (sm, sf) = _pair(_species('starter'));
      final starterBill = breedCost(sm, sf, wineOnly);
      expect(starterBill['wine'], isNull);
      expect(canAffordBreed(starterBill, wineOnly), isFalse);
    });

    test('rarer pairs cost more', () {
      final (cm, cf) = _pair(_species('c-mon'));
      final (rm, rf) = _pair(_species('r-are', rarity: CreatureRarity.rare));
      double total(Map<String, double> m) =>
          m.values.fold<double>(0, (a, b) => a + b);
      const rich = {'fish': 999.0, 'fur': 999.0};
      expect(total(breedCost(rm, rf, rich)),
          greaterThan(total(breedCost(cm, cf, rich))));
    });

    test('billed ONCE for the pair, not once per parent', () {
      final (m, f) = _pair(_species('starter'));
      final cost = breedCost(m, f, {'fish': 999});
      expect(cost['fish'], kSpeciesBalance.of(CreatureRarity.common).breedGoods);
    });

    test('a free price bills nothing at all', () {
      // Dev-tunable to 0 in Species-Budget → Breeding: that has to mean free,
      // not "one unit of the richest good".
      kSpeciesBalance = kSpeciesBalance.copyWith({
        CreatureRarity.common:
            kSpeciesBalance.of(CreatureRarity.common).copyWith(breedGoods: 0),
      });
      final (m, f) = _pair(_species('starter'));
      expect(breedCost(m, f, {'fish': 999}), isEmpty);
    });
  });

  group('paying it', () {
    test('spends the good you have MOST of', () {
      final (m, f) = _pair(_species('starter'));
      final cost = breedCost(m, f, {'fish': 4, 'fur': 999});
      expect(cost['fur'], isNotNull);
      expect(cost['fish'], isNull);
    });

    test('a store that cannot cover it still names the shortfall', () {
      // goodsCost demands the remainder rather than silently shrinking the
      // bill, so the refusal can quote a real number.
      final (m, f) = _pair(_species('starter'));
      final stock = {'fish': 1.0, 'fur': 1.0};
      final cost = breedCost(m, f, stock);
      expect(canAffordBreed(cost, stock), isFalse);
      expect(cost.values.fold<double>(0, (a, b) => a + b),
          kSpeciesBalance.of(CreatureRarity.common).breedGoods);
    });

    test('an affordable bill reads as affordable', () {
      final (m, f) = _pair(_species('starter'));
      const stock = {'fish': 999.0, 'fur': 999.0};
      expect(canAffordBreed(breedCost(m, f, stock), stock), isTrue);
    });

    test('the label names the goods, so a refusal says what to gather', () {
      expect(breedCostLabel({'fish': 6, 'fur': 4}), '🐟 6 · 🦫 4');
    });
  });

  group('a species whose def has not loaded', () {
    test('falls back to era I rather than becoming unbreedable', () {
      // The cheapest, always-available bill. Era 0 would have no goods at all,
      // which would make the pair impossible to pay for.
      final orphan = _mob('nowhere', CreatureGender.male);
      expect(breedEra(orphan.species), 1);
      final cost = breedCost(orphan, orphan, {'fish': 999});
      expect(cost['fish'], isNotNull);
    });
  });
}
