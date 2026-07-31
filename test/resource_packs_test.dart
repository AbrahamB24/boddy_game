import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/goods_definitions.dart';
import 'package:boddygame/features/settlement/data/item_definitions.dart';
import 'package:boddygame/features/settlement/models/resource_model.dart';

// ── Ressourcenpakete (user 2026-07-30) ──────────────────────
// "Die Pakete kommen ins Inventar und können dann eingelöst werden. Werden diese
// eingelöst, kann das Lagermaximum überstiegen werden, aber in dieser Zeit wird
// nicht produziert."
//
// Two rules, and the second one is the reason the first is safe to allow. Both
// fail SILENTLY if broken: a tick that trims the overflow deletes a campaign
// reward five seconds after it was opened, and a production cap that keeps
// paying while a store is over the line turns the package into free storage.
void main() {
  ResourceModel res({
    double wood = 0,
    double stone = 0,
    double gold = 0,
    Map<String, double> goods = const {},
  }) => ResourceModel(
    settlementId: 's',
    wood: wood,
    stone: stone,
    gold: gold,
    goods: goods,
    lastUpdatedAt: DateTime(2026),
  );

  group('production stops at the ceiling, the overflow stays', () {
    const caps = {'wood': 500.0, 'stone': 500.0, 'fish': 100.0};

    test('below the ceiling, everything produced is banked', () {
      final before = res(wood: 100);
      final after = before.withProductionCapped(res(wood: 180), caps);
      expect(after.wood, 180);
    });

    test('production is trimmed at the ceiling, not past it', () {
      final before = res(wood: 460);
      // The engine wanted to add 90; only 40 fit.
      final after = before.withProductionCapped(res(wood: 550), caps);
      expect(after.wood, 500);
    });

    test('ABOVE the ceiling, nothing of it is produced — and nothing is lost',
        () {
      // The heart of it: a redeemed Wagon put 1500 wood into a 500 store.
      final before = res(wood: 1500);
      final after = before.withProductionCapped(res(wood: 1590), caps);
      expect(after.wood, 1500, reason: 'no production while over the line');
      expect(after.wood, isNot(500), reason: 'and the reward is NOT trimmed');
    });

    test('spending always goes through, full store or not', () {
      // A refinery eating its input, a bill being paid: consumption is not
      // production and must never be blocked by a full store.
      final before = res(wood: 1500);
      final after = before.withProductionCapped(res(wood: 1200), caps);
      expect(after.wood, 1200);
    });

    test('the overflow drains and production resumes by itself', () {
      var stock = res(wood: 520);
      // Spend 40 (now 480, under the 500 ceiling)…
      stock = stock.withProductionCapped(res(wood: 480), caps);
      expect(stock.wood, 480);
      // …and the next tick produces again, up to the ceiling.
      stock = stock.withProductionCapped(res(wood: 600), caps);
      expect(stock.wood, 500);
    });

    test('a resource with no ceiling is never limited', () {
      final before = res(goods: {'honey': 900});
      final after = before.withProductionCapped(
        res(goods: {'honey': 1200}),
        caps,
      );
      expect(after.goods['honey'], 1200);
    });

    test('each resource is judged on its own', () {
      final before = res(wood: 900, stone: 100);
      final after = before.withProductionCapped(
        res(wood: 1000, stone: 200),
        caps,
      );
      expect(after.wood, 900, reason: 'over its ceiling: paused');
      expect(after.stone, 200, reason: 'under its own: unaffected');
    });

    test('overCapacity names exactly what is paused', () {
      final stock = res(wood: 700, stone: 500, goods: {'fish': 20});
      expect(stock.overCapacity(caps), ['wood']);
      // AT the ceiling is not OVER it — that store is merely full.
      expect(res(wood: 500).overCapacity(caps), isEmpty);
    });
  });

  group('the packages themselves', () {
    test('the ladders are exactly the ones the author gave', () {
      // user 2026-07-30, verbatim. Written out rather than derived, because a
      // "sensible" formula is exactly what these replaced.
      expect(kPackSizes[PackClass.build], [10, 100, 500, 1000, 5000, 10000]);
      expect(kPackSizes[PackClass.gold], [10, 50, 100, 500, 1000]);
      expect(kPackSizes[PackClass.luxury], [10, 50, 100]);
    });

    test('each resource is on the ladder its KIND implies', () {
      // Wood and stone are the settlement's own fields; a raw and the element
      // assembled from it are what buildings cost; `supply` is the luxury half.
      expect(packClassOf('wood'), PackClass.build);
      expect(packClassOf('stone'), PackClass.build);
      expect(packClassOf('gold'), PackClass.gold);
      expect(packClassOf('fish'), PackClass.luxury);
      expect(packClassOf('fur'), PackClass.luxury);
      for (final g in kGoodsDefs.values) {
        expect(
          packClassOf(g.id),
          g.isSupply ? PackClass.luxury : PackClass.build,
          reason: '${g.id} (${g.kind.name})',
        );
      }
      // Something that is not a resource at all falls to the smallest ladder
      // rather than inventing a 10 000-unit package.
      expect(packClassOf('nonsense'), PackClass.luxury);
    });

    test('one package per rung, for every resource', () {
      final packs = buildPackDefs();
      for (final id in ['wood', 'stone', 'gold', ...kGoodsDefs.keys]) {
        for (final amount in packSizesFor(id)) {
          final def = packs[packId(id, amount)];
          expect(def, isNotNull, reason: '$id/$amount');
          expect(def!.kind, ItemKind.resourcePack);
          expect(def.resourceId, id);
          expect(def.magnitude, amount.toDouble());
          expect(def.name, contains('$amount'));
        }
      }
      // …and nothing else: a fish 5000 would be a ladder nobody wrote.
      expect(packs[packId('fish', 5000)], isNull);
    });

    test('the biggest build package does not fit an early store', () {
      // Which is the point: the overflow rule is what makes a milestone reward
      // worth its full value to a settlement that has not built past 500 yet.
      expect(packSizesFor('wood').last, greaterThan(500));
      expect(packSizesFor('fish').last, lessThan(packSizesFor('wood').last));
    });

    test('the glyph follows the FIGURE, not the rung', () {
      // So 100 of anything looks like 100 of anything else — a luxury's top rung
      // and a build resource's third rung are the same size of parcel.
      expect(packEmoji(100), packEmoji(100));
      expect(packEmoji(10), isNot(packEmoji(10000)));
      expect(packEmoji(packSizesFor('fish').last),
          packEmoji(100));
    });

    test('a package cannot be crafted or bought', () {
      // Otherwise the overflow rule becomes a way around storage rather than a
      // reward for a battle.
      for (final def in buildPackDefs().values) {
        expect(def.ingredients, isEmpty, reason: def.id);
        expect(def.buyPrice, 0, reason: def.id);
        expect(def.sellPrice, 0, reason: def.id);
      }
    });

    test('every package is in the live roster and says what it holds', () {
      for (final def in buildPackDefs().values) {
        expect(kItemDefs[def.id], isNotNull, reason: def.id);
        expect(def.description, contains(def.magnitude.toStringAsFixed(0)));
        expect(def.name, isNotEmpty);
      }
    });

    test('packages did not displace the hand-written items', () {
      for (final id in ['minor_potion', 'potion', 'revive_charm', 'catch_lure']) {
        expect(kItemDefs[id], isNotNull, reason: id);
      }
    });

    test('packages are in the FALLBACK roster, not just the live map', () {
      // The bug this closes (user 2026-07-30: "wenn ich auf +package drücke,
      // kommen die Items und nicht die Ressourcen"): GameDefsController._merge
      // rebuilds the live map as `clear() + kFallbackItemDefs + database rows`
      // on every load, so a def that lives only in kItemDefs exists until the
      // game first reaches Supabase — and then quietly does not.
      for (final id in buildPackDefs().keys) {
        expect(kFallbackItemDefs[id], isNotNull, reason: '$id survives a merge');
      }
    });

    test('a package is recognisable from its ID alone', () {
      for (final amount in packSizesFor('wood')) {
        final parsed = parsePackId(packId('wood', amount));
        expect(parsed?.resourceId, 'wood');
        expect(parsed?.amount, amount);
      }
      expect(isPackId('minor_potion'), isFalse);
      expect(parsePackId('pack_wood_lots'), isNull);
      expect(parsePackId('pack__500'), isNull);
      expect(parsePackId('pack_wood_0'), isNull);
      // A good whose own id carried an underscore still reads back whole.
      expect(parsePackId('pack_iron_ore_1000')?.resourceId, 'iron_ore');
      expect(parsePackId('pack_iron_ore_1000')?.amount, 1000);
    });

    test('a merge keeps them — the exact operation the loader performs', () {
      final live = <String, ItemDef>{}
        ..clear()
        ..addAll(kFallbackItemDefs)
        ..addAll(<String, ItemDef>{});
      expect(live[packId('wood', 500)]?.kind, ItemKind.resourcePack);
    });
  });
}
