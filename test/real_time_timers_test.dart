import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/core/tuning/game_tuning.dart';
import 'package:boddygame/features/settlement/models/energy_model.dart';
import 'package:boddygame/features/settlement/models/placed_building.dart';
import 'package:boddygame/features/settlement/models/resource_model.dart';
import 'package:boddygame/features/settlement/services/game_engine.dart';

// Timers run in REAL time (user 2026-09-28: "die Zeit hängt von der Energie ab
// … 10h sind nicht wirklich 10h"): energy only scales what is PRODUCED.
void main() {
  setUp(() => GameTuning.i.debugClear());
  tearDown(() => GameTuning.i.debugClear());

  final t0 = DateTime.utc(2026, 9, 28, 8);

  EnergyModel energyAt(double pct) => EnergyModel(
    settlementId: 's',
    energyPct: pct,
    lastUpdatedAt: t0,
  );

  ResourceModel stock() => ResourceModel(
    settlementId: 's',
    wood: 0,
    stone: 0,
    gold: 0,
    goods: const {},
    lastUpdatedAt: t0,
  );

  PlacedBuilding site({double required = 36000}) => PlacedBuilding(
    id: 'site',
    settlementId: 's',
    buildingTypeId: 'small_house',
    gridX: 0,
    gridY: 0,
    level: 1,
    constructionSecondsRequired: required,
    constructionSecondsBuilt: 0,
    isComplete: false,
    placedAt: t0,
  );

  GameTickResult tick(double energyPct, Duration span) => GameEngine.tick(
    energyAt(energyPct),
    stock(),
    [site()],
    t0.add(span),
    workshopPower: const {},
  );

  test('a 10 h build takes 10 h at an empty pool', () {
    final r = tick(0, const Duration(hours: 10));
    expect(r.buildings.single.isComplete, isTrue);
  });

  test('…and at a full pool it takes exactly the same', () {
    final at100 = tick(100, const Duration(hours: 10));
    expect(at100.buildings.single.isComplete, isTrue);
    final short = tick(100, const Duration(hours: 9));
    expect(short.buildings.single.isComplete, isFalse);
    final emptyShort = tick(0, const Duration(hours: 9));
    expect(emptyShort.buildings.single.isComplete, isFalse);
  });

  test('the tick reports the real hours it spans', () {
    expect(tick(0, const Duration(hours: 3)).realHours, closeTo(3, 1e-9));
  });

  test('production still follows energy: an empty pool makes nothing', () {
    final r = GameEngine.tick(
      energyAt(0),
      stock(),
      const [],
      t0.add(const Duration(hours: 2)),
      workshopPower: const {'wood': 10},
    );
    expect(r.resources.wood, 0);
  });
}
