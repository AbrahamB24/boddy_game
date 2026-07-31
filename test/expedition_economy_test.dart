import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/area.dart';
import 'package:boddygame/features/settlement/data/gather_defs.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/services/capture_math.dart';
import 'package:boddygame/features/creatures/services/expedition_economy.dart';

const _spot = ResourceSpotDef(
  id: 'sp',
  resource: 'wood',
);

const _area = AreaDef(
  id: 'a',
  name: 'A',
  emoji: '🌲',
  order: 1,
  battleStage: 1,
  dangerLevel: 1,
  spots: [_spot],
);

void main() {
  group('syntheticCreature', () {
    test('carries exactly the given stats — absent stats are 0, not 10', () {
      final c = syntheticCreature({CreatureStat.production: 50});
      expect(c.statValue(CreatureStat.production), 50);
      // statValue floors at 1, but the synthetic zeroes the base so no
      // phantom default-10 power leaks into estimates.
      expect(c.statValue(CreatureStat.carry), 1);
    });
  });

  group('estimateGatherDay', () {
    test('sustainable yield is regen-capped, burst is stock+regen-capped', () {
      final members = [
        // Deliberately far past what a spot can regrow: with the per-resource
        // dials a "strong" group is one that empties the spot several times a
        // day, which takes a much higher gather stat than it used to.
        syntheticCreature({
          CreatureStat.gathering: 2000,
          CreatureStat.carry: 200,
        }),
      ];
      final est = estimateGatherDay(
        area: _area,
        spot: _spot,
        members: members,
        reactionHours: 0,
      );
      // Strong group hauls far more than regen — sustainable clamps to
      // regen*24, burst to capacity+regen*24.
      expect(est.sustainableYield, closeTo(gatherDefFor(_spot.resource).regenPerHour * 24, 1e-6));
      expect(
        est.burstDayYield,
        closeTo(gatherDefFor(_spot.resource).spotCapacity + gatherDefFor(_spot.resource).regenPerHour * 24, 1e-6),
      );
      expect(est.burstDayYield, greaterThan(est.sustainableYield));
    });

    test('weak demand is throughput-capped instead', () {
      final members = [
        syntheticCreature({
          CreatureStat.gathering: 25,
          CreatureStat.carry: 10,
        }),
      ];
      final est = estimateGatherDay(
        area: _area,
        spot: _spot,
        members: members,
        reactionHours: 2,
      );
      final demand = est.haulPerTrip * est.tripsPerDay;
      expect(est.sustainableYield, closeTo(demand, 1e-6));
      expect(demand, lessThan(gatherDefFor(_spot.resource).regenPerHour * 24));
    });

    test('reaction delay lowers trips/day', () {
      final members = [
        syntheticCreature({
          CreatureStat.gathering: 50,
          CreatureStat.carry: 50,
        }),
      ];
      final fast = estimateGatherDay(
        area: _area,
        spot: _spot,
        members: members,
        reactionHours: 0,
      );
      final slow = estimateGatherDay(
        area: _area,
        spot: _spot,
        members: members,
        reactionHours: 4,
      );
      expect(slow.tripsPerDay, lessThan(fast.tripsPerDay));
    });
  });

  group('estimateCaptureDay', () {
    // Redesign (user 2026-07-17): six FIXED-duration variants. A longer
    // variant is no longer the throughput king — its draw is more finds PER
    // TRIP, better rare odds, and running unattended (AFK). Many short trips,
    // watched closely, out-catch one long trip per day. So the invariant is
    // per-TRIP finds, not per-day.
    test('a longer variant brings more monsters per trip', () {
      final members = [syntheticCreature({CreatureStat.catchRate: 90})];
      final short = estimateCaptureDay(
        area: _area,
        members: members,
        option: kCaptureHuntOptions.first,
        reactionHours: 1,
      );
      final long = estimateCaptureDay(
        area: _area,
        members: members,
        option: kCaptureHuntOptions.last,
        reactionHours: 1,
      );
      expect(long.huntDuration, greaterThan(short.huntDuration));
      expect(
        kCaptureHuntOptions.last.finds,
        greaterThan(kCaptureHuntOptions.first.finds),
      );
    });

    test('an attended dedicated slot clears the 5/day floor', () {
      // The lower bound still matters — a dedicated hunter should catch
      // plenty. The upper 5–8 anchor is deliberately exceeded now (user
      // asked for "deutlich mehr Monster"), so only the floor is asserted.
      final est = estimateCaptureDay(
        area: _area,
        members: [syntheticCreature({CreatureStat.catchRate: 90})],
        option: kCaptureHuntOptions.first,
        qteSuccess: 0.85,
        reactionHours: 1,
      );
      expect(est.catchesPerDay, greaterThanOrEqualTo(5));
    });
  });
}
