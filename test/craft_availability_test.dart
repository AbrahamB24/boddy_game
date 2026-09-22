import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/item_definitions.dart';
import 'package:boddygame/features/settlement/services/crafting.dart';

// The Crafting page's "you can make N" and "missing 6 Frame" (user 2026-09-20,
// "Variante 4"): what the store pays for, what is short, and which rail button
// an item sits under.
void main() {
  ItemDef recipe(Map<String, double> ingredients, {double supply = 0}) =>
      ItemDef(
        id: 't',
        name: 'T',
        emoji: '🧪',
        description: '',
        ingredients: ingredients,
        supplyCost: supply,
        craftSeconds: 60,
      );

  const stock = {'fish': 96.0, 'meat': 40.0, 'frame': 24.0};

  group('craftableCount', () {
    test('is the scarcest ingredient, rounded down', () {
      // 96 / 5 = 19, 40 / 2 = 20 -> 19.
      expect(craftableCount(recipe({'fish': 5, 'meat': 2}), 2, stock), 19);
      // 24 / 4 = 6 wins over 40 / 2.
      expect(craftableCount(recipe({'meat': 2, 'frame': 4}), 2, stock), 6);
    });

    test('is 0 when one ingredient is missing altogether', () {
      expect(craftableCount(recipe({'fish': 1, 'clay': 1}), 2, stock), 0);
    });

    test('a free recipe is unlimited', () {
      expect(craftableCount(recipe({}), 2, stock), kCraftableCap);
    });

    test('supplies are paid from the era goods added together', () {
      // Era I luxury is fish alone: 96 / 10 = 9.
      expect(craftableCount(recipe({}, supply: 10), 1, stock), 9);
    });
  });

  group('craftShortfall', () {
    test('names what is missing and by how much', () {
      final r = recipe({'fish': 10, 'meat': 6, 'frame': 30});
      expect(craftShortfall(r, 2, stock), {'frame': 6.0});
    });

    test('scales with the number ordered', () {
      final r = recipe({'meat': 3});
      expect(craftShortfall(r, 2, stock, n: 13), isEmpty); // 39 <= 40
      expect(craftShortfall(r, 2, stock, n: 14), {'meat': 2.0}); // 42 - 40
    });

    test('is empty when the store covers it', () {
      expect(craftShortfall(recipe({'fish': 3}), 2, stock), isEmpty);
    });
  });

  group('craftGroupOf', () {
    test('every item kind has a rail button', () {
      for (final k in ItemKind.values) {
        expect(craftGroupOf(k), isA<CraftGroup>());
      }
    });

    test('heals, revives, cures and packs land where their name says', () {
      expect(craftGroupOf(ItemKind.heal), CraftGroup.heal);
      expect(craftGroupOf(ItemKind.revive), CraftGroup.revive);
      expect(craftGroupOf(ItemKind.cureStatus), CraftGroup.cures);
      expect(craftGroupOf(ItemKind.cureDebuffs), CraftGroup.cures);
      expect(craftGroupOf(ItemKind.resourcePack), CraftGroup.packs);
    });

    test('everything craftable is grouped', () {
      for (final d in kItemDefs.values) {
        expect(CraftGroup.values, contains(craftGroupOf(d.kind)));
      }
    });
  });
}
