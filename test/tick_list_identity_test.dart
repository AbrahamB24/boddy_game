import 'package:boddygame/features/settlement/models/energy_model.dart';
import 'package:boddygame/features/settlement/models/placed_building.dart';
import 'package:boddygame/features/settlement/models/resource_model.dart';
import 'package:boddygame/features/settlement/services/daily_tasks.dart'
    show dateKeyFor;
import 'package:boddygame/features/settlement/services/game_engine.dart';
import 'package:flutter_test/flutter_test.dart';

// The settlement controller keys its derived caches (road network, buildable
// region) on the IDENTITY of its buildings list, and the map's terrain follows
// the region. A tick that hands back an equal-but-new list every 10 s threw all
// of that away for nothing — so a tick that changes no building must return the
// very list it was given.
void main() {
  final start = DateTime.utc(2026, 1, 1);

  GameTickResult tick(List<PlacedBuilding> buildings) => GameEngine.tick(
    EnergyModel(
      settlementId: 's',
      stepsToday: 1000000,
      stepsDayKey: dateKeyFor(start.toLocal()),
      lastUpdatedAt: start,
    ),
    ResourceModel(settlementId: 's', wood: 0, stone: 0, lastUpdatedAt: start),
    buildings,
    start.add(const Duration(minutes: 1)),
    workshopPower: const {},
  );

  PlacedBuilding building({required bool complete}) => PlacedBuilding(
    id: complete ? 'done' : 'site',
    settlementId: 's',
    buildingTypeId: 'unknown_type',
    gridX: 0,
    gridY: 0,
    level: 1,
    constructionSecondsRequired: 100000,
    constructionSecondsBuilt: 0,
    isComplete: complete,
    placedAt: start,
  );

  test('nothing under construction: the same list comes back', () {
    final buildings = [building(complete: true)];
    expect(identical(tick(buildings).buildings, buildings), isTrue);
  });

  test('a site making progress: a new list, the finished ones untouched', () {
    final done = building(complete: true);
    final buildings = [done, building(complete: false)];
    final next = tick(buildings).buildings;
    expect(identical(next, buildings), isFalse);
    expect(identical(next.first, done), isTrue);
    expect(next.last.constructionSecondsBuilt, greaterThan(0));
  });
}
