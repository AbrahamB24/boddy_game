import 'package:flutter_test/flutter_test.dart';
import 'package:boddygame/features/settlement/data/goods_definitions.dart';
import 'package:boddygame/features/settlement/data/resource_icons.dart';

import 'package:boddygame/features/creatures/models/area.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/models/spot_state.dart';
import 'package:boddygame/features/creatures/services/gather_math.dart';
import 'package:boddygame/features/settlement/data/gather_defs.dart';

// statValue floors at 1 and defaults a MISSING stat to 10, so we set every
// stat these tests read explicitly (woodcutting/mining/carry). A value of 0
// still reads back as 1 (the floor) — the model has no "zero skill".
CreatureInstance _mob({int gathering = 0, int carry = 0}) => CreatureInstance(
  id: 'c${gathering}_$carry',
  userId: 'u',
  speciesId: 's',
  gender: CreatureGender.male,
  statBase: {
    CreatureStat.gathering: gathering.toDouble(),
    CreatureStat.carry: carry.toDouble(),
  },
  statSlope: const {},
);

const _spot = ResourceSpotDef(id: 'sp', resource: 'wood');

/// The wood dials every expectation below is derived from, so a balance tweak
/// in Dev Mode retunes the game without breaking the tests.
final _wood = gatherDefFor('wood');

const _area = AreaDef(
  id: 'a',
  name: 'A',
  emoji: '🌲',
  order: 1,
  battleStage: 1,
  dangerLevel: 2,
  spots: [_spot],
);

void main() {
  group('gather math', () {
    test('ONE stat mines everything, whatever the resource', () {
      // Four era-I trades (woodcutting/mining/prospecting/luxuryProduction)
      // became a single `gathering` stat 2026-07-25 — how hard a resource is to
      // get lives in its dials now, not in a separate skill.
      final m = _mob(gathering: 25);
      expect(gatherPowerOf(m), 25);
    });

    test('every spot on the bundled map is gatherable and has an emoji', () {
      // The planner and the trip cards look the emoji up unconditionally.
      //
      // Asked through the SHARED lookup since 2026-07-30: `fish` and `fur` left
      // kResourceEmoji when it turned out `fur` was defined in two tables with
      // two different animals. The invariant is unchanged — every spot has a
      // glyph — but there is now one place that answers it.
      for (final area in kFallbackAreaDefs) {
        for (final spot in area.spots) {
          expect(resourceEmoji(spot.resource), isNot('📦'), reason: spot.id);
          expect(spot.emoji, resourceEmoji(spot.resource), reason: spot.id);
        }
      }
      // Something that is not a resource falls back rather than inventing one.
      expect(resourceEmoji('bp'), '📦');
    });

    test('no resource is defined twice, with two different glyphs', () {
      // The bug this closes (user 2026-07-30: "Zudem ist das Icon nicht das
      // gleiche"): kResourceEmoji said 🦊 for fur, kGoodsDefs said 🦫, and each
      // screen showed whichever table it happened to read first.
      for (final id in kResourceEmoji.keys) {
        expect(kGoodsDefs.containsKey(id), isFalse,
            reason: '$id is defined in BOTH tables — pick one');
      }
    });

    test('carry is PORTERS, not kilos: one point holds many units', () {
      // The whole point of the 2026-07-25 rework — carry 60 used to mean 60
      // wood, which made a trip worth less than a minute of production.
      final plan = planGather(
        area: _area,
        spot: _spot,
        members: [_mob(gathering: 50, carry: 40), _mob(carry: 20)],
        availableStock: 100000,
      );
      expect(plan.loadCap, 60 * _wood.unitsPerCarry);
      expect(plan.amount, plan.loadCap); // limited by carry, not by stock
      expect(plan.isViable, isTrue);
      expect(plan.loadCap, greaterThan(60),
          reason: 'bulk must beat the old 1:1 weight');
    });

    test('bulk hauls far more per carry point than luxury or gold', () {
      // "Bauressourcen … in grösseren Mengen … Luxus oder sogar Gold nur in
      // kleinen Mengen."
      expect(gatherDefFor('wood').unitsPerCarry,
          greaterThan(gatherDefFor('fish').unitsPerCarry));
      expect(gatherDefFor('fish').unitsPerCarry,
          greaterThan(gatherDefFor('gold').unitsPerCarry));
      // …and gold is the slowest per stat point.
      expect(gatherDefFor('gold').secondsPerUnitPerStat,
          greaterThan(gatherDefFor('wood').secondsPerUnitPerStat));
    });

    test('low stock caps the haul below carry', () {
      final plan = planGather(
        area: _area,
        spot: _spot,
        members: [_mob(gathering: 50, carry: 100)],
        availableStock: 25,
      );
      expect(plan.amount, 25); // limited by stock, not the 100 carry
    });

    test('rate is stat points ÷ seconds-per-unit-per-stat', () {
      final plan = planGather(
        area: _area,
        spot: _spot,
        members: [_mob(gathering: 50, carry: 10)],
        availableStock: 100000,
      );
      expect(plan.ratePerHour,
          closeTo(50 * 3600 / _wood.secondsPerUnitPerStat, 1e-6));
      // Twice the stat, twice the speed — no reference-stat curve any more.
      final double_ = planGather(
        area: _area,
        spot: _spot,
        members: [_mob(gathering: 100, carry: 10)],
        availableStock: 100000,
      );
      expect(double_.ratePerHour, closeTo(plan.ratePerHour * 2, 1e-6));
    });

    test('an empty spot yields no viable trip', () {
      final empty = planGather(
        area: _area,
        spot: _spot,
        members: [_mob(gathering: 50, carry: 30)],
        availableStock: 0,
      );
      expect(empty.amount, 0);
      expect(empty.isViable, isFalse);
    });

    test('duration includes per-danger travel overhead', () {
      final plan = planGather(
        area: _area,
        spot: _spot,
        members: [_mob(gathering: 50, carry: 30)],
        availableStock: 100000,
      );
      // Mining time from the dials plus danger-scaled travel — computed from
      // the constants so balance tweaks don't break the test.
      final rate = _wood.ratePerHour(50);
      final miningSeconds = (_wood.loadCap(30) / rate) * 3600;
      final travelSeconds = _area.dangerLevel * kTravelSecondsPerDanger;
      expect(plan.duration.inSeconds, (miningSeconds + travelSeconds).round());
    });
  });

  group('spot regen', () {
    test('regenerates over time, clamped to capacity', () {
      final t0 = DateTime(2026, 1, 1, 12);
      final state = SpotState(spotId: 'sp', stock: 100, lastUpdatedAt: t0);
      expect(
        state.currentStock(_spot, t0.add(const Duration(hours: 2))),
        closeTo(100 + _wood.regenPerHour * 2, 1e-9),
      );
      // 1000h would overshoot; clamp to the resource's spot capacity.
      expect(
        state.currentStock(_spot, t0.add(const Duration(hours: 1000))),
        _wood.spotCapacity,
      );
    });

    test('afterMining bakes in regen then removes the haul', () {
      final t0 = DateTime(2026, 1, 1, 12);
      final state = SpotState(spotId: 'sp', stock: 100, lastUpdatedAt: t0);
      final next = state.afterMining(_spot, 50, t0.add(const Duration(hours: 1)));
      expect(next.stock, closeTo(100 + _wood.regenPerHour - 50, 1e-9));
    });
  });
}
