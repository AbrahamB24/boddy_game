import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/models/placed_building.dart';

// ── Gebäude pausieren (user 2026-08-01) ─────────────────────
// "ich will gebäude pausieren können"
//
// A paused building produces nothing and therefore consumes nothing — the
// switch you want when a refinery eats wood faster than you can cut it, and
// un-staffing it would cost you the posting.
//
// The flag itself is the whole feature: SettlementController.workshopPower and
// productionSources skip a paused building, which is what makes the pause reach
// the tick, the header rate, the refinery burn and the breakdown at once. What
// is pinned here is that the flag SURVIVES the round trip — a pause that is
// forgotten on reload is worse than no pause, because the building looks
// stopped and is not.
void main() {
  PlacedBuilding building({bool paused = false}) => PlacedBuilding(
    id: 'b1',
    settlementId: 's',
    buildingTypeId: 'wood_camp_e1',
    gridX: 3,
    gridY: 4,
    level: 2,
    constructionSecondsRequired: 60,
    constructionSecondsBuilt: 60,
    isComplete: true,
    isPaused: paused,
    placedAt: DateTime(2026),
  );

  test('a new building runs — pausing is something you do', () {
    expect(building().isPaused, isFalse);
    expect(PlacedBuilding.fromMap({
      'id': 'b',
      'settlement_id': 's',
      'building_type_id': 't',
      'grid_x': 0,
      'grid_y': 0,
      'level': 1,
      'construction_seconds_required': 1,
      'construction_seconds_built': 1,
      'is_complete': true,
      'placed_at': DateTime(2026).toIso8601String(),
    }).isPaused, isFalse, reason: 'a row written before the column existed');
  });

  test('the pause survives the round trip through the database', () {
    final row = building(paused: true).toMap();
    expect(row['is_paused'], isTrue);
    final back = PlacedBuilding.fromMap({
      ...row,
      'placed_at': DateTime(2026).toIso8601String(),
    });
    expect(back.isPaused, isTrue);
  });

  test('copyWith can flip it, and leaves everything else alone', () {
    final b = building();
    final paused = b.copyWith(isPaused: true);
    expect(paused.isPaused, isTrue);
    expect(paused.level, b.level);
    expect(paused.gridX, b.gridX);
    // …and an unrelated edit must not silently un-pause it.
    expect(paused.copyWith(level: 3).isPaused, isTrue);
  });
}
