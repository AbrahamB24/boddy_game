import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/services/healing_cost.dart';
import 'package:boddygame/features/settlement/data/goods_definitions.dart';
import 'package:boddygame/features/settlement/models/resource_model.dart';

CreatureInstance _mob({int hp = 60, int? currentHp}) {
  final c = CreatureInstance(
    id: 'c',
    userId: 'u',
    speciesId: 's',
    gender: CreatureGender.male,
    statBase: {CreatureStat.hp: hp.toDouble()},
    statSlope: const {},
  );
  if (currentHp != null) c.currentHp = currentHp;
  return c;
}

void main() {
  group('goods are era-scoped', () {
    test('an era deals in everything introduced up to it, cumulatively', () {
      // Cumulative on purpose: a new era ADDS to the economy, it doesn't
      // replace it — fish still matter in era III.
      expect(goodsForEra(1).map((g) => g.id), ['fish', 'fur']);
      expect(goodsForEra(5).map((g) => g.id), containsAll(['fish', 'fur']));
    });

    test('a settlement earlier than any good still has currency', () {
      // Defensive: era 0 shouldn't leave the sinks with nothing to charge.
      expect(goodsForEra(0), isNotEmpty);
    });

    test('a bill is paid from the goods you HAVE, richest first', () {
      // Spends the surplus, protects the scarce good — what a player would do.
      expect(goodsCost(10, 1, {'fish': 50, 'fur': 3}), {'fish': 10.0});
      expect(goodsCost(0, 1, {'fish': 50}), isEmpty);
    });

    test('THE deadlock: one missing good must never block a cost', () {
      // The bug this replaced: costs were split evenly and ceiled per good, so
      // EVERY bill demanded at least 1 of EVERY era good. Era I's goods are
      // fish AND fur, region 1 has no fur spot, and fur first appears behind
      // the region-1 boss — so running out of fur stopped healing entirely,
      // with no way to get more. Exactly the trap the Healing Hut was ungated
      // to avoid (docs/balancing.md §4b).
      final cost = goodsCost(10, 1, {'fish': 50, 'fur': 0});
      expect(cost['fur'], isNull, reason: 'must not demand a good you lack');
      expect(cost['fish'], 10.0);
    });

    test('it spills onto the next good when the richest runs out', () {
      expect(goodsCost(10, 1, {'fish': 4, 'fur': 30}), {'fur': 10.0});
      expect(goodsCost(10, 1, {'fish': 6, 'fur': 4}), {'fish': 6.0, 'fur': 4.0});
    });

    test('an unaffordable bill still names the shortfall', () {
      // It must NOT silently shrink to what you can afford — the caller's
      // affordability check has to fail.
      final cost = goodsCost(10, 1, {'fish': 2, 'fur': 1});
      expect(cost.values.fold<double>(0, (a, b) => a + b), 10.0);
      expect(canAfford(cost, {'fish': 2, 'fur': 1}), isFalse);
    });

    test('whole units only, and never rounds down to free', () {
      final cost = goodsCost(0.2, 1, {'fish': 50, 'fur': 50});
      expect(cost.values.every((v) => v == v.roundToDouble()), isTrue);
      expect(cost.values.fold<double>(0, (a, b) => a + b), 1.0);
    });

    test('a broke settlement gets a deterministic bill, not map order', () {
      expect(goodsCost(4, 1, {}), goodsCost(4, 1, {}));
      expect(goodsCost(4, 1, {}).values.fold<double>(0, (a, b) => a + b), 4.0);
    });
  });

  group('healing costs goods', () {
    test('a creature at full health is free', () {
      expect(healGoodsFor(_mob()), 0);
      expect(healCost([_mob()], {'fish': 99, 'fur': 99}), isEmpty);
    });

    test('a full-HP creature is not billed for the -1 sentinel', () {
      // currentHp = -1 MEANS full. Reading the raw field instead of `hp` bills
      // a brand-new creature for maxHp + 1 points of damage it never took.
      final fresh = _mob(hp: 60);
      expect(fresh.currentHp, -1);
      expect(healGoodsFor(fresh), 0);
    });

    test('cost is proportional to missing HP', () {
      final scratch = _mob(hp: 60, currentHp: 55);
      final mauled = _mob(hp: 60, currentHp: 10);
      expect(healGoodsFor(scratch), lessThan(healGoodsFor(mauled)));
      expect(healGoodsFor(scratch), 5 * healGoodsPerHp(CreatureRarity.common));
    });

    test('a K.O. costs more than surviving on 1 HP', () {
      // Otherwise there is no reason to ever retreat.
      final alive = _mob(hp: 60, currentHp: 1);
      final ko = _mob(hp: 60, currentHp: 0);
      expect(healGoodsFor(ko), greaterThan(healGoodsFor(alive)));
    });

    test('a scratch still costs something — never free through rounding', () {
      // 1 HP × 0.1 = 0.1 total.
      final cost = healCost(
        [_mob(hp: 60, currentHp: 59)],
        {'fish': 99, 'fur': 99},
      );
      expect(cost.values.fold<double>(0, (a, b) => a + b), 1.0);
    });

    test('a hurt team heals on fish alone when the fur has run out', () {
      // THE deadlock, at the healing level: region 1 has no fur spot, so this
      // is the state every early player ends up in.
      final cost = healCost([_mob(hp: 60, currentHp: 20)], {
        'fish': 99,
        'fur': 0,
      });
      expect(canAfford(cost, {'fish': 99, 'fur': 0}), isTrue);
    });

    test('and is still refused when there are no supplies at all', () {
      final cost = healCost([_mob(hp: 60, currentHp: 20)], {
        'fish': 0,
        'fur': 0,
      });
      expect(canAfford(cost, {'fish': 0, 'fur': 0}), isFalse);
    });
  });

  group('healing takes time', () {
    test('a healthy creature needs no treatment', () {
      expect(healDuration(_mob()), Duration.zero);
      expect(healDurationFor([_mob()]), Duration.zero);
    });

    test('a full-HP creature is not billed time for the -1 sentinel', () {
      // Same trap as the cost side: currentHp = -1 MEANS full.
      final fresh = _mob(hp: 60);
      expect(fresh.currentHp, -1);
      expect(healDuration(fresh), Duration.zero);
    });

    test('duration scales with missing HP', () {
      final scratch = _mob(hp: 60, currentHp: 55);
      final mauled = _mob(hp: 60, currentHp: 10);
      expect(healDuration(mauled), greaterThan(healDuration(scratch)));
      expect(healDuration(scratch).inSeconds, (5 * healSecondsPerHp(CreatureRarity.common)).round());
    });

    test('a K.O. takes longer than surviving on 1 HP', () {
      // Time, like cost, has to make retreating worth it.
      final alive = _mob(hp: 60, currentHp: 1);
      final ko = _mob(hp: 60, currentHp: 0);
      expect(healDuration(ko), greaterThan(healDuration(alive)));
    });

    test('healing all takes as long as the WORST case, not the sum', () {
      // Treatment runs per creature and in parallel — a scratched monster must
      // not wait on a K.O.'d one.
      final scratch = _mob(hp: 60, currentHp: 55);
      final ko = _mob(hp: 60, currentHp: 0);
      expect(healDurationFor([scratch, ko]), healDuration(ko));
    });

    test('a trial costs minutes, a wipe costs the best part of an hour', () {
      // Anchored on docs/balancing.md §4b: a trial takes ~55% of a ~60 HP
      // monster. The gap between the two IS the reason to retreat.
      final afterTrial = _mob(hp: 60, currentHp: 27);
      final wiped = _mob(hp: 60, currentHp: 0);
      expect(afterTrial.hp, greaterThan(0), reason: 'survived, did not faint');
      expect(healDuration(afterTrial).inMinutes, inInclusiveRange(5, 25));
      expect(healDuration(wiped).inMinutes, greaterThan(40));
    });

    test('being treated is a real state with time left', () {
      final c = _mob(hp: 60, currentHp: 10)
        ..healingUntil = DateTime.now().add(const Duration(minutes: 10));
      expect(c.isHealing, isTrue);
      expect(c.healingRemaining.inMinutes, closeTo(10, 1));

      // An elapsed timer is no longer "healing" — that's what makes lazy
      // resolution work after the app was closed.
      c.healingUntil = DateTime.now().subtract(const Duration(minutes: 1));
      expect(c.isHealing, isFalse);
      expect(c.healingRemaining, Duration.zero);
    });

    test('a creature not being treated has no phantom timer', () {
      final c = _mob(hp: 60, currentHp: 10);
      expect(c.isHealing, isFalse);
      expect(c.healingRemaining, Duration.zero);
    });
  });

  group('goods storage survives the jsonb move', () {
    Map<String, dynamic> row(Map<String, dynamic> extra) => {
      'settlement_id': 's',
      'wood': 1.0,
      'stone': 2.0,
      'gold': 3.0,
      'last_updated_at': '2026-07-16T00:00:00.000Z',
      ...extra,
    };

    test('reads the jsonb blob', () {
      final r = ResourceModel.fromMap(
        row({
          'goods': {'fish': 4, 'fur': 5},
        }),
      );
      expect(r.goods, {'fish': 4.0, 'fur': 5.0});
    });

    test('falls back to the legacy columns on a pre-migration row', () {
      // Migration 0006 may not have run yet — an existing player's fish must
      // not silently read as zero.
      final r = ResourceModel.fromMap(row({'fish': 7, 'fur': 8}));
      expect(r.goods, {'fish': 7.0, 'fur': 8.0});
    });

    test('an unknown good round-trips — no column needed for a new resource', () {
      // THE point of the jsonb move: a later era's resource must persist
      // without a schema change.
      final r = ResourceModel.fromMap(
        row({
          'goods': {'bronze': 12},
        }),
      );
      expect(r.goods['bronze'], 12.0);
      expect(r.toMap()['goods'], {'bronze': 12.0});
      expect(r.asMap['bronze'], 12.0);
      expect(r.deduct({'bronze': 2}).goods['bronze'], 10.0);
    });
  });
}
