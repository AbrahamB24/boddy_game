import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/data/goods_definitions.dart';
import 'package:boddygame/features/settlement/models/energy_model.dart';
import 'package:boddygame/features/settlement/models/resource_model.dart';
import 'package:boddygame/features/settlement/services/game_engine.dart';

// The era ladder (user 2026-07-24): every era from II on unlocks ONE fresh raw
// AND ONE building element. The element assembles the era before's element with
// the era before's raw — element(N) = 2 × element(N−1) + 2 × rawForEra(N−1) —
// and the era's OWN fresh raw is a separate build ingredient (building(N) costs
// element(N) + rawForEra(N)), folded into the element only next era. Two
// properties still have to hold or the shape is wrong: wood and stone stay
// exactly equal forever, and each newer raw is needed in half the quantity of
// the one before it.
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
    lastUpdatedAt: DateTime.utc(2026, 7, 22),
  );

  EnergyModel energy(DateTime at) => EnergyModel(
    settlementId: 's',
    currentEnergy: kMaxEnergy,
    lastUpdatedAt: at,
  );

  GameTickResult tickOneHour(
    ResourceModel start,
    Map<String, double> workshopPower,
  ) {
    final t0 = start.lastUpdatedAt;
    return GameEngine.tick(
      energy(t0),
      start,
      const [],
      t0.add(const Duration(hours: 1)),
      workshopPower: workshopPower,
    );
  }

  group('the era ladder', () {
    test('every era from II on has exactly one element', () {
      for (var order = 2; order <= 8; order++) {
        final e = elementForEra(order);
        expect(e, isNotNull, reason: 'era $order needs an element');
        expect(e!.refinedFrom, isNotEmpty);
      }
      expect(elementForEra(1), isNull, reason: 'era I builds from raw wood');
    });

    test('each element is 2× the one below plus 2× the PREVIOUS era\'s raw', () {
      for (var order = 3; order <= 8; order++) {
        final element = elementForEra(order)!;
        final below = elementForEra(order - 1)!;
        // The raw folded in is the era-BEFORE's fresh raw, not this era's.
        final raw = rawForEra(order - 1)!;
        expect(
          element.refinedFrom,
          {below.id: 2.0, raw.id: 2.0},
          reason: '${element.id} must contain ${below.id} + ${raw.id}',
        );
      }
      // The first rung is the only one made of two raws: era I's wood and stone,
      // now both starting resources.
      expect(elementForEra(2)!.refinedFrom, {'wood': 2.0, 'stone': 2.0});
    });

    test('eras II–VIII each unlock their own fresh raw; era I uses the fields', () {
      expect(
        rawForEra(1),
        isNull,
        reason: 'wood AND stone are ResourceModel fields',
      );
      for (var order = 2; order <= 8; order++) {
        final r = rawForEra(order);
        expect(r, isNotNull, reason: 'era $order needs a fresh raw');
        expect(r!.refinedFrom, isEmpty, reason: 'a raw is gathered, not made');
      }
      // Era II's fresh raw (clay) and era VIII's (aether) bracket the ladder.
      expect(rawForEra(2)!.id, 'clay');
      expect(rawForEra(8)!.id, 'aether');
    });

    test('wood and stone stay exactly equal — all the way to era VIII', () {
      for (var order = 2; order <= 8; order++) {
        final raw = rawCostOf(elementForEra(order)!.id);
        expect(
          raw['wood'],
          raw['stone'],
          reason: 'era $order element must weigh wood and stone alike',
        );
      }
      final top = rawCostOf('vault');
      expect(top['wood'], 128);
      expect(top['stone'], 128);
    });

    test('the older the resource, the more of it you need', () {
      final top = rawCostOf('vault');
      expect(top, {
        'wood': 128,
        'stone': 128,
        'clay': 64,
        'lime': 32,
        'ore': 16,
        'coal': 8,
        'sand': 4,
        'crystal': 2,
      });
      // 382 raw units for one era-VIII element against 4 for an era-II one.
      expect(top.values.reduce((a, b) => a + b), 382);
      expect(rawCostOf('frame').values.reduce((a, b) => a + b), 4);
    });

    test('raws and elements are never billed as supplies', () {
      // goodsCost pays for healing/dungeon entry. Spending clay or a finished
      // wall there would silently stall construction.
      final bill = goodsCost(40, 8, {
        'fish': 100.0,
        'fur': 100.0,
        'clay': 999.0,
        'frame': 999.0,
      });
      expect(bill.keys, isNot(contains('clay')));
      expect(bill.keys, isNot(contains('frame')));
      for (final g in goodsForEra(8)) {
        expect(g.kind, GoodsKind.supply);
      }
      // …but the player still HOLDS them: the header reads materialsForEra.
      expect(materialsForEra(3).map((g) => g.id), containsAll(['frame', 'clay']));
      expect(materialsForEra(1), isEmpty, reason: 'era I has neither');
    });
  });

  group('assembly', () {
    test('a workshop burns its inputs: 3 frames/h costs 6 wood + 6 stone', () {
      final start = res(wood: 100, stone: 100);
      final r = tickOneHour(start, {'frame': 3});
      expect(r.resources.goods['frame'], closeTo(3, 1e-9));
      expect(r.resources.wood, closeTo(100 - 6, 1e-9));
      expect(r.resources.stone, closeTo(100 - 6, 1e-9));
    });

    test('it can eat wood and stone gathered in the SAME tick', () {
      final r = tickOneHour(res(), {'wood': 20, 'stone': 20, 'frame': 3});
      expect(r.resources.goods['frame'], closeTo(3, 1e-9));
      expect(r.resources.wood, closeTo(14, 1e-9));
    });

    test('no input, no output — elements are never made from nothing', () {
      final r = tickOneHour(res(wood: 100), {'frame': 3}); // no stone
      expect(r.resources.goods['frame'] ?? 0, 0);
      expect(r.resources.wood, 100);
    });

    test('the scarcest input throttles it instead of going negative', () {
      final r = tickOneHour(res(wood: 100, stone: 4), {'frame': 3});
      expect(r.resources.goods['frame'], closeTo(2, 1e-9)); // 4 stone / 2
      expect(r.resources.stone, closeTo(0, 1e-9));
      expect(r.resources.wood, closeTo(96, 1e-9));
    });

    test('the ladder resolves in era order: daub eats this tick\'s frames', () {
      final start = res(wood: 100, stone: 100, goods: {'clay': 10});
      final r = tickOneHour(start, {'frame': 6, 'daub': 2});
      expect(r.resources.goods['daub'], closeTo(2, 1e-9));
      expect(r.resources.goods['frame'], closeTo(6 - 4, 1e-9));
      expect(r.resources.goods['clay'], closeTo(10 - 4, 1e-9));
    });

    test('the hourly rate shows wood NET of what the workshop eats', () {
      final rates = GameEngine.hourlyRates(
        energy(DateTime.utc(2026, 7, 22)),
        {'wood': 20, 'stone': 20, 'frame': 3},
      );
      expect(rates['frame'], closeTo(3, 1e-9));
      expect(rates['wood'], closeTo(20 - 6, 1e-9));
      expect(rates['stone'], closeTo(20 - 6, 1e-9));
    });
  });


  // ── What the main screen's header strip is allowed to show ──
  // The strip is exactly seven cells in EVERY era (user 2026-07-29: this era's
  // build resources, this era's luxuries, gold, energy, housing) and it is a
  // single non-scrolling row — so "two build + two luxuries per era" is not a
  // nice property of the data, it is the layout's precondition. Break it and
  // the header silently overflows or reflows.
  group('current-era header set', () {
    test('every era from II on has exactly one element and one raw', () {
      for (var era = 2; era <= 8; era++) {
        final pair = buildGoodsOfEra(era);
        expect(pair.length, 2, reason: 'era $era build pair');
        expect(pair.where((g) => g.isElement).length, 1, reason: 'era $era');
        expect(pair.where((g) => g.kind == GoodsKind.raw).length, 1,
            reason: 'era $era');
      }
    });

    test('era I builds from wood and stone, so it has no build GOODS', () {
      expect(buildGoodsOfEra(1), isEmpty);
    });

    test('every era introduces exactly two luxuries', () {
      for (var era = 1; era <= 8; era++) {
        expect(luxuriesOfEra(era).length, 2, reason: 'era $era luxuries');
        expect(luxuriesOfEra(era).every((g) => g.isSupply), isTrue);
      }
    });

    test('the era set is NOT cumulative — that is what goodsForEra is for', () {
      expect(luxuriesOfEra(3).map((g) => g.id), isNot(contains('fish')));
      expect(goodsForEra(3).map((g) => g.id), contains('fish'));
    });
  });
}
