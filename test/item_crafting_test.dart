import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/item_definitions.dart';
import 'package:boddygame/features/settlement/services/crafting.dart';

// Items Phase 1 (user 2026-07-25): recipes name CONCRETE luxury ingredients,
// items carry an effect kind + magnitude, and the heal path stays compatible.
void main() {
  group('craftCost', () {
    test('charges the literal ingredients when a recipe names them', () {
      const item = ItemDef(
        id: 'x',
        name: 'X',
        emoji: '🧪',
        kind: ItemKind.heal,
        magnitude: 40,
        ingredients: {'wine': 2, 'herbs': 1},
        craftSeconds: 1200,
        description: '',
      );
      final cost = craftCost(item, 3, const {'wine': 10, 'herbs': 10});
      expect(cost, {'wine': 2, 'herbs': 1});
    });

    test('falls back to abstract supplyCost when no ingredients', () {
      const item = ItemDef(
        id: 'y',
        name: 'Y',
        emoji: '🧪',
        kind: ItemKind.heal,
        magnitude: 40,
        supplyCost: 6,
        craftSeconds: 1200,
        description: '',
      );
      final cost = craftCost(item, 1, const {'fish': 100});
      expect(cost, isNotEmpty);
      expect(cost.values.fold<double>(0, (s, v) => s + v), closeTo(6, 0.001));
    });
  });

  group('ItemDef model', () {
    test('heal getters stay compatible with the old heal path', () {
      const heal = ItemDef(
        id: 'h', name: 'H', emoji: '🧪', description: '',
        kind: ItemKind.heal, magnitude: 40, craftSeconds: 1,
      );
      const buff = ItemDef(
        id: 'b', name: 'B', emoji: '💪', description: '',
        kind: ItemKind.buff, magnitude: 0.3, craftSeconds: 1,
      );
      expect(heal.isHeal, isTrue);
      expect(heal.healHp, 40);
      expect(buff.isHeal, isFalse);
      expect(buff.healHp, 0);
    });

    test('round-trips through the DB row incl. new fields', () {
      const item = ItemDef(
        id: 'lure', name: 'Lure', emoji: '🎏', description: 'catch',
        kind: ItemKind.catchBoost, magnitude: 0.25, battleUsable: false,
        ingredients: {'fish': 2}, craftSeconds: 1800,
        buyPrice: 40, sellPrice: 12,
      );
      final r = ItemDef.fromDefRow(item.toDefRow());
      expect(r.kind, ItemKind.catchBoost);
      expect(r.magnitude, 0.25);
      expect(r.ingredients, {'fish': 2});
      expect(r.buyPrice, 40);
      expect(r.sellPrice, 12);
    });

    test('legacy heal_hp row maps onto a heal item', () {
      final r = ItemDef.fromDefRow({
        'id': 'old', 'name': 'Old', 'craft_seconds': 1200, 'heal_hp': 55,
      });
      expect(r.kind, ItemKind.heal);
      expect(r.healHp, 55);
    });

    test('bundled items use luxury ingredients', () {
      expect(kFallbackItemDefs['minor_potion']!.ingredients, isNotEmpty);
      expect(kFallbackItemDefs['revive_charm']!.kind, ItemKind.revive);
    });
  });
}
