import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/item_definitions.dart';
import 'package:boddygame/features/settlement/models/settlement.dart';
import 'package:boddygame/features/settlement/services/crafting.dart';

// Crafting is what the repurposed crafting stat (ex-`research`) finally does.
// These pin the rules that are easy to get quietly wrong: billing against the
// era's goods rather than a hardcoded resource, and never letting the bag hold
// something that isn't there.

const _potion = ItemDef(
  id: 'p',
  name: 'Potion',
  emoji: '🧪',
  description: '',
  supplyCost: 6,
  craftSeconds: 1200,
  kind: ItemKind.heal,
  magnitude: 40,
);

void main() {
  group('settlement model', _modelTests);

  group('cost', () {
    test('bills the era goods the settlement actually has', () {
      // The whole point of routing through goodsCost: a recipe names no
      // resource, so a new era's goods work with no change to the recipe.
      final cost = craftCost(_potion, 1, {'fish': 100, 'fur': 0});
      expect(cost.keys, ['fish']);
      expect(cost['fish'], 6);
    });

    test('spreads onto a second good when the richest runs short', () {
      final cost = craftCost(_potion, 1, {'fish': 4, 'fur': 50});
      expect(cost.values.fold<double>(0, (s, v) => s + v), 6);
    });

    test('an empty larder still names a price rather than crafting free', () {
      final cost = craftCost(_potion, 1, const {});
      expect(cost.values.fold<double>(0, (s, v) => s + v), 6);
    });
  });

  group('progress', () {
    test('no crafters means no ETA, not an infinite one', () {
      // The caller has to say "post a monster in the Workshop". A bar that
      // simply never moves reads as a bug — the old research screen learned
      // this the hard way.
      expect(craftSecondsAt(_potion, 0), isNull);
      expect(craftSecondsAt(_potion, 1200), isNotNull);
    });

    test('more crafting power finishes sooner', () {
      expect(
        craftSecondsAt(_potion, 2400)!,
        lessThan(craftSecondsAt(_potion, 1200)!),
      );
    });

    test('the jumpstart shortens the requirement, not the rate', () {
      // Same rule the rest of the intro follows: a temporary multiplier on the
      // requirement, never a change to the underlying rate.
      expect(
        craftSecondsAt(_potion, 1200, timeScale: 0.2)!,
        closeTo(craftSecondsAt(_potion, 1200)! * 0.2, 1e-9),
      );
      expect(craftComplete(_potion, 240, timeScale: 0.2), isTrue);
      expect(craftComplete(_potion, 240), isFalse);
    });

    test('progress is clamped to 0..1', () {
      expect(craftProgress(_potion, -5), 0);
      expect(craftProgress(_potion, 99999), 1);
      expect(craftProgress(_potion, 600), closeTo(0.5, 1e-9));
    });
  });

  group('inventory', () {
    test('removing the last one drops the key, not a zero', () {
      // A 0 left behind would render as a bag entry you cannot use.
      final bag = removeItem({'p': 1}, 'p')!;
      expect(bag.containsKey('p'), isFalse);
      expect(itemCount(bag), 0);
    });

    test('removing what you do not have returns null, never a silent no-op', () {
      expect(removeItem(const {}, 'p'), isNull);
      expect(removeItem(const {'other': 3}, 'p'), isNull);
    });

    test('add and remove round-trip', () {
      var bag = addItem(const {}, 'p', 2);
      expect(bag['p'], 2);
      bag = removeItem(bag, 'p')!;
      expect(bag['p'], 1);
    });

    test('json load drops zero and negative counts', () {
      expect(inventoryFromJson({'a': 2, 'b': 0, 'c': -1}), {'a': 2});
      expect(inventoryFromJson(null), isEmpty);
    });
  });

  group('use', () {
    test('heals only what is missing — no overflow', () {
      expect(healFromItem(_potion, 12), 12);
      expect(healFromItem(_potion, 500), 40);
    });

    test('a potion on a full-health monster is refused, not wasted', () {
      expect(canUseOn(_potion, 0), isFalse);
      expect(canUseOn(_potion, 1), isTrue);
    });

    test('the bundled big potion is worse per ingredient than the small one', () {
      // Concentration costs a premium on purpose: if the big one were also
      // more efficient, the small one would be retired the day it unlocked.
      final small = kFallbackItemDefs['minor_potion']!;
      final big = kFallbackItemDefs['potion']!;
      double units(ItemDef d) =>
          d.ingredients.values.fold<double>(0.0, (s, v) => s + v);
      expect(big.healHp / units(big), lessThan(small.healHp / units(small)));
      expect(big.healHp, greaterThan(small.healHp));
    });
  });
}

// ── Model round-trip ────────────────────────────────────────
// The crafting columns are behind migration 0011; the model must survive their
// absence, because Postgrest rejects a whole row over one unknown column and a
// pre-0011 profile still has to load.

Map<String, dynamic> _row([Map<String, dynamic> extra = const {}]) => {
  'id': 's',
  'user_id': 'u',
  'name': 'Home',
  'era_index': 0,
  'main_building_level': 1,
  'created_at': '2026-01-01T00:00:00Z',
  ...extra,
};

void _modelTests() {
  test('loads with the crafting columns missing (pre-0011)', () {
    final s = SettlementModel.fromMap(_row());
    expect(s.activeCraftId, isNull);
    expect(s.craftSecondsBuilt, 0);
    expect(s.items, isEmpty);
  });

  test('round-trips a craft job and a bag', () {
    final s = SettlementModel.fromMap(_row({
      'active_craft_id': 'minor_potion',
      'craft_seconds_built': 300.0,
      'items': {'minor_potion': 2},
    }));
    expect(s.activeCraftId, 'minor_potion');
    expect(s.items['minor_potion'], 2);
    final back = SettlementModel.fromMap(_row(s.toMap()..['created_at'] =
        '2026-01-01T00:00:00Z'));
    expect(back.craftSecondsBuilt, 300.0);
    expect(back.items['minor_potion'], 2);
  });

  test('withCraft resets progress — banked work cannot move recipes', () {
    // Otherwise a player banks seconds on the cheap potion and cashes them in
    // on the expensive one.
    final s = SettlementModel.fromMap(_row({
      'active_craft_id': 'minor_potion',
      'craft_seconds_built': 900.0,
    }));
    final switched = s.withCraft('potion');
    expect(switched.activeCraftId, 'potion');
    expect(switched.craftSecondsBuilt, 0);
  });

  test('copyWith never silently clears the active recipe', () {
    // copyWith's `??` cannot tell "clear it" from "not provided" — which is
    // exactly why withCraft exists.
    final s = SettlementModel.fromMap(_row({'active_craft_id': 'potion'}));
    expect(s.copyWith(craftSecondsBuilt: 5).activeCraftId, 'potion');
    expect(s.withCraft(null).activeCraftId, isNull);
  });
}
