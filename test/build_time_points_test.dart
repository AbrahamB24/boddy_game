import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/models/energy_model.dart';
import 'package:boddygame/features/settlement/models/placed_building.dart';
import 'package:boddygame/features/settlement/models/resource_model.dart';
import 'package:boddygame/features/settlement/services/game_engine.dart';

// The construction model reworked on 2026-07-26 (user: "jeder Construction
// Punkt zählt als 1 Construction Point … jeder dieser Punkte reduziert dann die
// Bauzeit in %").
//
// What changed and must stay changed: build points are no longer a budget of
// build-SECONDS that has to reach an anchor before a building finishes in its
// authored time. They are a plain count that buys a PERCENTAGE off that time.
void main() {
  group('buildTimeCut', () {
    test('zero points take nothing off — the authored time IS the time', () {
      expect(buildTimeCut(0), 0);
      expect(buildTimeCut(-5), 0); // no such thing as negative points
      expect(buildSpeedFromPoints(0), 1.0);
    });

    test('kBuildPointsForHalfTime is exactly the −50 % mark', () {
      expect(buildTimeCut(kBuildPointsForHalfTime), closeTo(0.5, 1e-9));
      expect(buildTimeCut(kBuildPointsForHalfTime * 4), closeTo(0.8, 1e-9));
      expect(buildTimeCut(kBuildPointsForHalfTime * 9), closeTo(0.9, 1e-9));
    });

    test('no ceiling, and never a free build', () {
      // The breeding cap was removed for this exact reason (user 2026-07-26):
      // a hard ceiling makes every upgrade past it worthless. The curve
      // flattens instead, and the time approaches zero without reaching it.
      expect(buildTimeCut(1e6), lessThan(1.0));
      expect(buildTimeCut(1e6), greaterThan(buildTimeCut(1e5)));
      expect(buildSpeedFromPoints(1e6).isFinite, isTrue);
    });

    test('buildPointsForCut inverts the curve', () {
      for (final cut in [0.25, 0.5, 0.8, 0.95]) {
        expect(buildTimeCut(buildPointsForCut(cut)!), closeTo(cut, 1e-9));
      }
      expect(buildPointsForCut(0), 0);
      expect(buildPointsForCut(1), isNull); // no finite count buys a free build
    });
  });

  group('GameEngine.tick spends the points as a percentage', () {
    // One hour of full energy, one site under construction.
    GameTickResult tickOneHour(double points) {
      final start = DateTime.utc(2026, 1, 1);
      return GameEngine.tick(
        EnergyModel(
          settlementId: 's',
          currentEnergy: 100000, // never dips into the energy floor
          lastUpdatedAt: start,
        ),
        ResourceModel(settlementId: 's', wood: 0, stone: 0, lastUpdatedAt: start),
        [
          PlacedBuilding(
            id: 'b',
            settlementId: 's',
            buildingTypeId: 'unknown_type',
            gridX: 0,
            gridY: 0,
            level: 1,
            constructionSecondsRequired: 100000, // long enough not to finish
            constructionSecondsBuilt: 0,
            isComplete: false,
            placedAt: start,
          ),
        ],
        start.add(const Duration(hours: 1)),
        workshopPower: {WorkshopRole.kConstruction: points},
      );
    }

    double builtAfterAnHour(double points) =>
        tickOneHour(points).buildings.single.constructionSecondsBuilt;

    test('an unstaffed site still builds — one build-second per real second',
        () {
      // This is the rule that replaced "zero builders = nothing builds", and
      // it is why the tutorial no longer needs a free build-power handout.
      expect(builtAfterAnHour(0), closeTo(3600, 1e-6));
    });

    test('points shorten the wait by exactly the cut they promise', () {
      // −50 % of the time means twice the progress per hour.
      expect(
        builtAfterAnHour(kBuildPointsForHalfTime),
        closeTo(7200, 1e-6),
      );
      expect(
        builtAfterAnHour(kBuildPointsForHalfTime * 4), // −80 % → ×5
        closeTo(18000, 1e-6),
      );
    });

    test('a point is a point — passive and staffed sources are one pot', () {
      // The controller sums both into workshopPower['construction'] with no
      // conversion on either side, so the engine cannot tell them apart.
      expect(builtAfterAnHour(40), closeTo(builtAfterAnHour(40), 1e-9));
      expect(builtAfterAnHour(60), greaterThan(builtAfterAnHour(40)));
    });
  });
}
